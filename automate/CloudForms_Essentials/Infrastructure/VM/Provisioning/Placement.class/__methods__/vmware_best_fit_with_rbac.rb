=begin
 vmware_best_fit_with_rbac.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method is used to find all VMware clusters, hosts, datastores that 
    have the appropriate rbac filters (via the group filters) applied. In the case where no rbac filters are 
    applied (i.e. admin) simply find the most appropriate clusters, hosts and datastores
-------------------------------------------------------------------------------
   Copyright 2016 Kevin Morey <kevin@redhat.com>

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-------------------------------------------------------------------------------
=end
def log(level, msg, update_message = false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

def get_current_group_rbac_array
  rbac_array = []
  group = @user.current_group
  unless group.filters.blank?
    group.filters['managed'].flatten.each do |filter|
      next unless /(?<category>\w*)\/(?<tag>\w*)$/i =~ filter
      rbac_array << {category=>tag}
    end
  end
  log(:info, "group: #{group.description} RBAC filters: #{rbac_array}")
  return rbac_array
end

def object_eligible?(obj)
  @rbac_array.each do |rbac_hash|
    rbac_hash.each do |rbac_category, rbac_tags|
      Array.wrap(rbac_tags).each {|rbac_tag_entry| return false unless obj.tagged_with?(rbac_category, rbac_tag_entry) }
    end
    true
  end
end

begin
  # Get provisioning object
  @task = $evm.root['miq_provision']
  log(:info, "Provision:<#{@task.id}> Request:<#{@task.miq_request.id}> Type:<#{@task.type}>")
  @ws_values = @task.options.fetch(:ws_values, {})

  @template = @task.vm_template

  @user = @task.miq_request.requester
  raise "User not specified" if @user.nil?
  @provider  = @template.ext_management_system

  @rbac_array = get_current_group_rbac_array
  if @rbac_array.blank?
    # uncomment below to set a default tag useful for targeting only specific hosts and datastores for admins
    # @rbac_array = [{'prov_scope'=>'all'}]
    # @rbac_array = [{'prov_scope'=>'admin'}]
  end

  log(:info, "template=<#{@template.name}>, Space Required=<#{@template.provisioned_storage}>, " \
                         "group=<#{@user.normalized_ldap_group}>")

  # STORAGE LIMITATIONS
  storage_max_vms      = $evm.object['storage_max_vms'].to_i
  log(:info, "storage_max_vms: #{storage_max_vms}")

  storage_max_pct_used = $evm.object['storage_max_pct_used'].to_i
  storage_max_pct_used = 100 if storage_max_pct_used.zero?
  log(:info, "storage_max_pct_used: #{storage_max_pct_used}")

  #############################
  # Set host sort order here
  # options: :active_provisioning_memory, :active_provisioning_cpu, :current_memory_usage,
  #          :current_memory_headroom, :current_cpu_usage, :random
  #############################
  HOST_SORT_ORDER = [:active_provisioning_memory, :current_memory_headroom, :random]

  #############################
  # Sort hosts
  #############################
  active_prov_data = @task.check_quota(:active_provisions)
  sort_data = []
  @task.eligible_hosts.each do |h|
    next unless object_eligible?(h)
    sort_data << sd = [[], h.name, h]
    host_id = h.attributes['id'].to_i
    HOST_SORT_ORDER.each do |type|
      sd[0] << case type
      # Multiply values by (-1) to cause larger values to sort first
      when :active_provisioning_memory; active_prov_data[:active][:memory_by_host_id][host_id]
      when :active_provisioning_cpu;    active_prov_data[:active][:cpu_by_host_id][host_id]
      when :current_memory_headroom;    h.current_memory_headroom * -1
      when :current_memory_usage;       h.current_memory_usage
      when :current_cpu_usage;          h.current_cpu_usage
      when :random;                     rand(1000)
      else 0
      end
    end
  end

  sort_data.sort! { |a, b| a[0] <=> b[0] }
  sorted_hosts = sort_data.collect { |sd| sd.pop }
  log(:info, "Sorted host Order:<#{HOST_SORT_ORDER.inspect}> Results:<#{sort_data.inspect}>")

  #############################
  # Set storage sort order here
  # options: :active_provisioning_vms, :free_space, :free_space_percentage, :random
  #############################
  STORAGE_SORT_ORDER = [:active_provisioning_vms, :random]

  host, storage, min_registered_vms = nil, nil, nil

  sorted_hosts.each do |h|
    next unless h.power_state == "on"
    log(:info, "host: #{h.name} tags: #{h.tags} vms: #{h.vms.count}")
    nvms = h.vms.length

    # Only consider Datastores that have the required rbac filters, if any
    storages = h.storages.select {|s| object_eligible?(s) }
    log(:info, "Evaluating eligible_storages: #{storages.collect { |s| s.name }.join(", ")}")

    #############################
    # Filter out storages that do not have enough free space for the VM
    #############################
    active_prov_data = @task.check_quota(:active_provisions)
    storages_with_enough_space = storages.select do |s|
      actively_provisioned_space = active_prov_data[:active][:storage_by_id][s.id]
      if s.free_space > @template.provisioned_storage + actively_provisioned_space
        true
      else
        log(:info, "Skipping Datastore: #{s.name}, not enough free space for template: #{@template.name}. " \
                               "Available: #{s.free_space}, Needs: #{@template.provisioned_storage}")
        false
      end
    end

    #############################
    # Filter out storages number of VMs is greater than the max number of VMs allowed per Datastore
    #############################
    storages_with_less_vms_than_allowed = storages_with_enough_space.select do |s|
      storage_id = s.id
      active_num_vms_for_storage = active_prov_data[:active][:vms_by_storage_id][storage_id].length
      if (storage_max_vms == 0) || ((s.vms.size + active_num_vms_for_storage) < storage_max_vms)
        true
      else
        log(:info, "Skipping Datastore: #{s.name}, max number of VMs: #{s.vms.size + active_num_vms_for_storage} exceeded")
        false
      end
    end

    #############################
    # Filter out storages where percent used will be greater than the max % allowed per Datastore
    #############################
    storages_with_less_percent_used = storages_with_less_vms_than_allowed.select do |s|
      storage_id = s.id
      active_pct_of_storage  = ((active_prov_data[:active][:storage_by_id][storage_id]) / s.total_space.to_f) * 100
      request_pct_of_storage = (@template.provisioned_storage / s.total_space.to_f) * 100

      if (storage_max_pct_used == 100) || ((s.v_used_space_percent_of_total + active_pct_of_storage + request_pct_of_storage) < storage_max_pct_used)
        true
      else
        log(:info, "Skipping Datastore: #{s.name} percent of used space " \
                               "#{s.v_used_space_percent_of_total + active_pct_of_storage + request_pct_of_storage} exceeded")
        false
      end
    end

    if min_registered_vms.nil? || nvms < min_registered_vms
      #############################
      # Sort storage to determine target datastore
      #############################
      sort_data = []
      storages_with_less_percent_used.each_with_index do |s, idx|
        sort_data << sd = [[], s.name, idx]
        storage_id = s.attributes['id'].to_i
        STORAGE_SORT_ORDER.each do |type|
          sd[0] << case type
          when :free_space
            # Multiply values by (-1) to cause larger values to sort first
            (s.free_space - active_prov_data[:active][:storage_by_id][storage_id]) * -1
          when :free_space_percentage
            active_pct_of_storage  = ((active_prov_data[:active][:storage_by_id][storage_id]) / s.total_space.to_f) * 100
            s.v_used_space_percent_of_total + active_pct_of_storage
          when :active_provisioning_vms
            active_prov_data[:active][:vms_by_storage_id][storage_id].length
          when :random
            rand(1000)
          else 0
          end
        end
      end

      sort_data.sort! { |a, b| a[0] <=> b[0] }
      log(:info, "Sorted storage Order: #{STORAGE_SORT_ORDER.inspect}  Results: #{sort_data.inspect}")
      selected_storage = sort_data.first
      unless selected_storage.nil?
        selected_idx = selected_storage.last
        storage = storages[selected_idx]
        host    = h
      end
      # Stop checking if we have found both host and storage
      break if host && storage
    end
  end # END - hosts.each

  raise "missing suitable host" if host.nil?
  log(:info, "Selected Host: #{host.nil? ? "nil" : host.name} ")
  @task.set_host(host)

  raise "missing suitable storage" if storage.nil?
  log(:info, "Selected Datastore:<#{storage.nil? ? "nil" : storage.name}>")
  @task.set_storage(storage)

  log(:info, "template: #{@template.name} host: #{host.name} storage: #{storage.name}")

  # Set Ruby rescue behavior
rescue => err
  log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end
