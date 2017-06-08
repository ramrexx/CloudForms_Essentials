# wait_for_poweroff.rb
#
# Description: This method checks to see if the VM has been powered off
#

# Get vm from root object
vm = $evm.root['vm']

if vm
  power_state = vm.attributes['power_state']
  ems = vm.ext_management_system
  $evm.log('info', "VM:<#{vm.name}> on provider:<#{ems.try(:name)} has Power State:<#{power_state}>")

  if power_state == 'off'
    $evm.root['ae_result'] = 'ok'
  else
    $evm.root['ae_result']     = 'retry'
    $evm.root['ae_retry_interval'] = '60.seconds'
    vm.refresh
  end
end
