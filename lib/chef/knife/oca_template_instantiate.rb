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
    class OCATemplateInstantiate < Knife

      include Knife::OCABase

      deps do
        require 'fog'
        require 'readline'
        require 'chef/json_compat'
        require 'chef/knife/bootstrap'
        Chef::Knife::Bootstrap.load_deps
      end

      banner "knife oca template instantiate ID (options)"

      attr_accessor :initial_sleep_delay
      attr_reader :server

      option :tags,
        :short => "-T T=V[,T=V,...]",
        :long => "--tags Tag=Value[,Tag=Value...]",
        :description => "The tags for this server",
        :proc => Proc.new { |tags| tags.split(',') }

      option :chef_node_name,
        :short => "-N NAME",
        :long => "--node-name NAME",
        :description => "The Chef node name for your new node"

      option :ssh_user,
        :short => "-x USERNAME",
        :long => "--ssh-user USERNAME",
        :description => "The ssh username",
        :default => "root"

      option :ssh_password,
        :short => "-P PASSWORD",
        :long => "--ssh-password PASSWORD",
        :description => "The ssh password"

      option :ssh_port,
        :short => "-p PORT",
        :long => "--ssh-port PORT",
        :description => "The ssh port",
        :default => "22",
        :proc => Proc.new { |key| Chef::Config[:knife][:ssh_port] = key }

      option :identity_file,
        :short => "-i IDENTITY_FILE",
        :long => "--identity-file IDENTITY_FILE",
        :description => "The SSH identity file used for authentication"

      option :prerelease,
        :long => "--prerelease",
        :description => "Install the pre-release chef gems"

      option :bootstrap_version,
        :long => "--bootstrap-version VERSION",
        :description => "The version of Chef to install",
        :proc => Proc.new { |v| Chef::Config[:knife][:bootstrap_version] = v }

      option :distro,
        :short => "-d DISTRO",
        :long => "--distro DISTRO",
        :description => "Bootstrap a distro using a template; default is 'chef-full'",
        :proc => Proc.new { |d| Chef::Config[:knife][:distro] = d },
        :default => "chef-full"

      option :template_file,
        :long => "--template-file TEMPLATE",
        :description => "Full path to location of a knife bootstrap template to use",
        :proc => Proc.new { |t| Chef::Config[:knife][:template_file] = t },
        :default => false

      option :run_list,
        :short => "-r RUN_LIST",
        :long => "--run-list RUN_LIST",
        :description => "Comma separated list of roles/recipes to apply",
        :proc => lambda { |o| o.split(/[\s,]+/) },
        :default => []

      option :json_attributes,
        :short => "-j JSON",
        :long => "--json-attributes JSON",
        :description => "A JSON string to be added to the first run of chef-client",
        :proc => lambda { |o| JSON.parse(o) },
        :default => {}

      option :host_key_verify,
        :long => "--[no-]host-key-verify",
        :description => "Verify host key, enabled by default.",
        :boolean => true,
        :default => true

      def tcp_test_ssh(hostname)
        tcp_socket = TCPSocket.new(hostname, config[:ssh_port])
        readable = IO.select([tcp_socket], nil, nil, 5)
        if readable
          Chef::Log.debug("sshd accepting connections on #{hostname}, banner is #{tcp_socket.gets}")
          yield
          true
        else
          false
        end
      rescue SocketError
        sleep 2
        false
      rescue Errno::ETIMEDOUT
        false
      rescue Errno::EPERM
        false
      rescue Errno::ECONNREFUSED
        sleep 2
        false
      # This happens on EC2 quite often
      rescue Errno::EHOSTUNREACH
        sleep 2
        false
      # This happens on EC2 sometimes
      rescue Errno::ENETUNREACH
        sleep 2
        false
      ensure
        tcp_socket && tcp_socket.close
      end

      def run
        $stdout.sync = true

        validate!

        template_id = @name_args.first
        @template = connection.templates.get(template_id)
        instance_id = @template.instantiate
        @server = connection.virtual_machines.get(instance_id)

        hashed_tags={}
        tags.map{ |t| key,val=t.split('='); hashed_tags[key]=val} unless tags.nil?

        # Always set the Name tag
        unless hashed_tags.keys.include? "Name"
          hashed_tags["Name"] = locate_config_value(:chef_node_name) || @server.id
        end

        #hashed_tags.each_pair do |key,val|
        #  connection.tags.create :key => key, :value => val, :resource_id => @server.id
        #end

        msg_pair("Instance ID", @server.id)
        msg_pair("Template", @template.name)
        msg_pair("# CPUs", @template.template['VCPU'])
        msg_pair("Memory", @template.template['MEMORY'])

        print "\n#{ui.color("Waiting for server", :magenta)}"

        # wait for it to be ready to do stuff
        @server.wait_for { print "."; ready? }

        puts("\n")

        msg_pair("Public DNS Name", @server.dns_name)
        msg_pair("Public IP Address", @server.template['NIC']['IP'])

        print "\n#{ui.color("Waiting for sshd", :magenta)}"

        fqdn = @server.dns_name

        print(".") until tcp_test_ssh(fqdn) {
          sleep @initial_sleep_delay ||= 10
          puts("done")
        }

        bootstrap_for_node(@server,fqdn).run

        puts "\n"
        msg_pair("Instance ID", @server.id)
        msg_pair("Flavor", @server.flavor_id)
        msg_pair("Image", @server.image_id)
        msg_pair("Public DNS Name", @server.dns_name)
        msg_pair("Public IP Address", @server.public_ip_address)
        msg_pair("Environment", config[:environment] || '_default')
        msg_pair("Run List", config[:run_list].join(', '))
        msg_pair("JSON Attributes",config[:json_attributes]) unless config[:json_attributes].empty?
      end

      def bootstrap_for_node(server,fqdn)
        bootstrap = Chef::Knife::Bootstrap.new
        bootstrap.name_args = [fqdn]
        bootstrap.config[:run_list] = config[:run_list]
        bootstrap.config[:ssh_user] = config[:ssh_user]
        bootstrap.config[:ssh_port] = config[:ssh_port]
        bootstrap.config[:identity_file] = config[:identity_file]
        bootstrap.config[:chef_node_name] = config[:chef_node_name] || server.id
        bootstrap.config[:prerelease] = config[:prerelease]
        bootstrap.config[:bootstrap_version] = locate_config_value(:bootstrap_version)
        bootstrap.config[:first_boot_attributes] = config[:json_attributes]
        bootstrap.config[:distro] = locate_config_value(:distro)
        bootstrap.config[:use_sudo] = true unless config[:ssh_user] == 'root'
        bootstrap.config[:template_file] = locate_config_value(:template_file)
        bootstrap.config[:environment] = config[:environment]
        # may be needed for vpc_mode
        bootstrap.config[:host_key_verify] = config[:host_key_verify]
        bootstrap
      end

      def tags
       tags = locate_config_value(:tags)
        if !tags.nil? and tags.length != tags.to_s.count('=')
          ui.error("Tags should be entered in a key = value pair")
          exit 1
        end
       tags
      end

    end
  end
end
