# wait_for_ip.rb
#
# Description: Wait for the IP address to be available on the VM before proceeding

class WaitForIP
  def initialize(handle = $evm)
    @handle = handle
  end

  def main
    vm = @handle.root["miq_provision"].try(:destination)
    vm ||= @handle.root["vm"]
    vm ? check_ip_addr_available(vm) : vm_not_found
  end

  def retry_method(vm)
    vm.refresh
    @handle.root['ae_result'] = 'retry'
    @handle.root['ae_retry_limit'] = 1.minute
  end

  def check_ip_addr_available(vm)
    ip_list = vm.ipaddresses
    @handle.log(:info, "Current Power State #{vm.power_state}")
    @handle.log(:info, "IP addresses for VM #{vm.name}: #{ip_list}")

    retry_method(vm) if ip_list.empty?
    ip_list.each do |ipaddr|
      if ipaddr.match(/^(169|0)/)
        retry_method(vm)
      else
        @handle.root['ae_result'] = 'ok'
      end
    end
  end

  def vm_not_found
    @handle.root['ae_result'] = 'error'
    @handle.log(:error, "VM not found")
  end
end

if __FILE__ == $PROGRAM_NAME
  WaitForIP.new.main
end
