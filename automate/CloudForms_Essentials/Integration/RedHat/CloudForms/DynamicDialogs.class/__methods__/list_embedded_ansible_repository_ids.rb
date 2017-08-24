# list_embedded_ansible_repository_ids.rb
#
# Author: Joshua Cornutt <jcornutt@redhat.com>
# License: GPL v3
#
# Description: List embedded Ansible repository IDs.
#

begin
  dialog_hash = Hash.new

  # Find all embedded Ansible repositories
  $evm.vmdb(:ManageIQ_Providers_EmbeddedAnsible_AutomationManager_ConfigurationScriptSource).all.each do |repo|
    dialog_hash[repo.id] = repo.name
  end

  # Sanity check
  if dialog_hash.blank?
    $evm.log(:warn, "User: #{$evm.root['user'].name} has no access to Configuration Script Sources")
    exit MIQ_WARN
  end

  $evm.object['values'] = dialog_hash
  $evm.log(:debug, "$evm.object['values']: #{$evm.object['values'].inspect}")

  # Exit Method
  exit MIQ_OK

# Set Ruby rescue behavior
rescue => err
  $evm.log(:error, "#{err.class} #{err}")
  $evm.log(:error, "#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end
