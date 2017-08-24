# list_embedded_ansible_playbook_ids.rb
#
# Author: Joshua Cornutt <jcornutt@redhat.com>
# License: GPL v3
#
# Description: List embedded Ansible playbook IDs.
#

begin
  dialog_hash = Hash.new

  # Find the Ansible repository object (if submitted)
  repo_id = $evm.root['dialog_ansible_repo_id']
  repo = $evm.vmdb(:ManageIQ_Providers_EmbeddedAnsible_AutomationManager_ConfigurationScriptSource).find_by_id(repo_id) rescue nil if repo_id
  playbooks = repo.configuration_script_payloads rescue nil if repo

  # Sanity checks
  unless repo && playbooks
    $evm.log(:warn, "User: #{$evm.root['user'].name} has no access to Playbooks for Repository ##{repo_id}")
    exit MIQ_WARN
  end

  # Populate the dropdown values
  playbooks.each { |playbook| dialog_hash[playbook.id] = playbook.name }

  $evm.object['values'] = dialog_hash
  $evm.log(:debug, "$evm.object['values']: #{$evm.object['values'].inspect}")

  # Exit Method
  exit (playbooks.empty?) ? MIQ_WARN : MIQ_OK

# Set Ruby rescue behavior
rescue => err
  $evm.log(:error, "#{err.class} #{err}")
  $evm.log(:error, "#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end
