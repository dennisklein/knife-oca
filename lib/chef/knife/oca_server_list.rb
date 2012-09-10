#
# Modified by:: Dennis Klein (<d.klein@gsi.de>)
#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Seth Chisamore (<schisamo@opscode.com>)
# Copyright:: Copyright (c) 2010-2011 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/knife/oca_base'

class Chef
  class Knife
    class OcaServerList < Knife

      include Knife::OcaBase

      banner "knife oca server list (options)"

      def run
        $stdout.sync = true

        #validate!

        server_list = [
          ui.color('ID', :bold),
          ui.color('Public IP', :bold),
          ui.color('Public DNS Name', :bold),
          ui.color('State', :bold),
          ui.color('# CPUs', :bold),
          ui.color('Memory', :bold),
          ui.color('Template', :bold)
        ]
        connection.virtual_machines.all('m').each do |server|
          server_list << server.id.to_s
          server_list << server.template['NIC']['IP'].to_s
          server_list << dns_reverse_lookup(server.template['NIC']['IP'].to_s)
          server_list << begin
            state = Fog::Compute::OCA::VirtualMachine::LCM_STATE[server.lcm_state.to_i]
            case state
            when 'SHUTDOWN', 'CANCEL', 'FAILURE', 'UNKNOWN'
              ui.color(Fog::Compute::OCA::VirtualMachine::SHORT_LCM_STATE[state], :red)
            when 'LCM_INIT', 'PROLOG', 'BOOT'
              ui.color(Fog::Compute::OCA::VirtualMachine::SHORT_LCM_STATE[state], :yellow)
            else
              ui.color(Fog::Compute::OCA::VirtualMachine::SHORT_LCM_STATE[state], :green)
            end
          end
          server_list << server.template['VCPU'].to_s
          server_list << server.template['MEMORY'].to_s
          server_list << begin
            template = connection.templates.get(server.template['TEMPLATE_ID'])
            template.name.to_s
          end
        end
        puts ui.list(server_list, :uneven_columns_across, 7)

      end
    end
  end
end
