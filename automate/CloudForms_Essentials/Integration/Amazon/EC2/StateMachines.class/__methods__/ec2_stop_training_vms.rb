
if Time.now.friday? && Time.now.hour > 18
  aws_vms = $evm.vmdb(:ManageIQ_Providers_Amazon_CloudManager_Vm).all.select {|vm| vm.name.include?('train')}
  $evm.log('info', "found #{aws_vms.count} VMs")

  aws_vms.each do |vm|
    $evm.log('info', "stopping AWS VM: #{vm.name} ems_ref: #{vm.ems_ref}")
    vm.stop
  end
end
