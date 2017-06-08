# wait_for_poweron.rb
#
# Description: This method retries until the VM has been powered on
#

# Get vm from root object
vm = $evm.root['vm']

if vm
  power_state = vm.attributes['power_state']
  ems = vm.ext_management_system
  $evm.log('info', "VM:<#{vm.name}> on provider:<#{ems.try(:name)} has Power State:<#{power_state}>")

  if power_state == 'on'
    $evm.root['ae_result'] = 'ok'
  else
    $evm.root['ae_result']     = 'retry'
    $evm.root['ae_retry_interval'] = '60.seconds'
    vm.refresh
  end
end
