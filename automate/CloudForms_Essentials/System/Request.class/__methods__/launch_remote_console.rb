=begin
 launch_remote_console.rb

 Author: Kevin Morey <kevin@redhat.com>

 Description: This method will launch an SSH|RDP session for a VM
 Required Parameters in the root object
   vm

 Optional Parameters in the root object
   ms_rdp = 'true|false'

-------------------------------------------------------------------------------
   Copyright 2017 Kevin Morey <kevin@redhat.com>

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
module CloudForms_Essentials
  module Automate
    module System
      module Request
        class LaunchRemoteConsole
          def initialize(handle = $evm)
            @handle = handle
          end

          def main
            @handle.log(:info, "Launching remote console #{remote_url} for vm #{vm.name}")
            vm.remote_console_url = remote_url
          end

          private

          def vm
            @handle.root['vm']
          end

          def remote_url
            if ms_rdp && vm.platform == 'windows'
              "#{protocol}://#{ms_rdp_ip}#{ms_rdp_uriopts}"
            elsif vm.platform == 'windows'
              "#{protocol}://#{ip}"
            else
              "#{protocol}://#{ssh_user}@#{ip}"
            end
          end

          def ms_rdp
            return true if @handle.root['ms_rdp'] =~ (/(true|t|yes|y|1)$/i)
          end

          def ssh_user
            user = $evm.root['ssh_user'] || $evm.root['dialog_ssh_user'] || $evm.root['user'].userid
            # too many ways to do this with different cloud providers, ssh keys, etc. But you could
            # do some fancy logic here
            #
            # case vm.vendor
            # when 'amazon'
            #   user = 'ec2-user'
            # when 'openstack'
            #   user = 'cloud-user'
            # else
            # end
            if user == 'admin'
              return 'root'
            end
            return user
          end

          def ms_rdp_ip
            # Microsoft Remote Desktop requires special uri handling. Check here:
            # https://docs.microsoft.com/en-us/windows-server/remote/remote-desktop-services/clients/remote-desktop-uri
            "full%20address=s:#{ip}"
          end

          def ms_rdp_uriopts
            # Add additional Microsoft Remote Desktop uri parameters
            "&screen%20mode%20id=i:1&use%20multimon=i:0"
          end

          def protocol
            vm.platform == 'windows' ? 'rdp' : 'ssh'
          end

          def ip
            # Default to using the public IP if available then fall back on the normal IP Address
            (vm.try(:floating_ip_addresses).try(:first) ||
            vm.try(:ipaddresses).try(:first)).tap do |ip|
              if ip.nil?
                raise "IP address not specified for #{vm.name}"
              end
            end
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  CloudForms_Essentials::Automate::System::Request::LaunchRemoteConsole.new.main
end
