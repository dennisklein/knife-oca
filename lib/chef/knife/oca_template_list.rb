#
# Author:: Dennis Klein (<d.klein@gsi.de>)
# Copyright:: Copyright (c) 2012 GSI Helmholtz Centre for Heavy Ion Research.
#
# Author:: Seth Chisamore (<schisamo@opscode.com>)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
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
    class OcaTemplateList < Knife

      include Knife::OcaBase

      banner "knife oca template list (options)"

      def run

        validate!

        flavor_list = [
          ui.color('ID', :bold),
          ui.color('Name', :bold),
          ui.color('Architecture', :bold),
          ui.color('CPUs', :bold),
          ui.color('Memory', :bold)
        ]
        connection.templates.all.each do |template|
          flavor_list << template.id.to_s
          flavor_list << template.name.to_s
          flavor_list << template.template['OS']['ARCH']
          flavor_list << template.template['VCPU']
          flavor_list << template.template['MEMORY']
        end
        puts ui.list(flavor_list, :uneven_columns_across, 5)
      end
    end
  end
end
