#
# Author:: Dennis Klein (<d.klein@gsi.de>)
# Copyright:: Copyright (c) 2012 GSI Helmholtz Centre for Heavy Ion Research.
#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Seth Chisamore (<schisamo@opscode.com>)
# Copyright:: Copyright (c) 2010-2011 Opscode, Inc.
#
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
require 'net/scp'

class Chef
  class Knife
    class OcaTemplateInstantiate < Knife

      include Knife::OcaBase

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
        :description => "Verify host key, disabled by default.",
        :boolean => true,
        :default => false 

      option :is_chef_server,
        :long => "--is-chef-server",
        :description => "Do not bootstrap, assume chef server is already installed, retrieve keys and configure knife",
        :boolean => true,
        :default => false

      option :chef_server_url_template,
        :long => "--chef-server-url-template",
        :description => "Some chef servers are proxied, therefor you can specify a url template. The default is 'https://FQDN:443'. FQDN gets replaced with the full qualified domain name of the node.",
        :default => "https://FQDN:443"

      option :retrieve_files,
        :long => "--retrieve-files",
        :description => "Comma-seperated list of files to be scped from the node into the current working directory, defaults are ['/etc/chef/validation.pem', '/etc/chef/webui.pem']. Is only performed if --is-chef-server is set!",
        :proc => lambda { |o| o.split(/[\s,]+/) },
        :default => ['/etc/chef/validation.pem', '/etc/chef/webui.pem']

      option :repository,
        :short => "-r REPO",
        :long => "--repository REPO",
        :description => "The path to your chef-repo, default is the current working directory.",
        :default => Dir.pwd

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
        @server = connection.virtual_machines.get(instance_id.to_s)

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
        msg_pair("Architecture", @template.template['OS']['ARCH'])

        print "\n#{ui.color("Waiting for server", :magenta)}"

        # wait for it to be ready to do stuff
        @server.wait_for { print "."; ready? }

        puts("done\n")

        fqdn = dns_reverse_lookup(@server.template['NIC']['IP'])
        
        msg_pair("Public DNS Name", fqdn)
        msg_pair("Public IP Address", @server.template['NIC']['IP'])

        print "\n#{ui.color("Waiting for sshd", :magenta)}"

        print(".") until tcp_test_ssh(fqdn) {
          sleep @initial_sleep_delay ||= 10
          puts("done")
        }

        if config[:is_chef_server] then
          retrieve_files(fqdn, config[:retrieve_files])
          configure_knife(fqdn)
        else
          bootstrap_for_node(@server,fqdn).run
        end

        puts "\n"
        msg_pair("Instance ID", @server.id)
        msg_pair("Template", @template.name)
        msg_pair("# CPUs", @template.template['VCPU'])
        msg_pair("Memory", @template.template['MEMORY'])
        msg_pair("Architecture", @template.template['OS']['ARCH'])
        msg_pair("Public DNS Name", fqdn)
        msg_pair("Public IP Address", @server.template['NIC']['IP'])
        msg_pair("Environment", config[:environment] || '_default')
        msg_pair("Run List", config[:run_list].join(', '))
        msg_pair("JSON Attributes",config[:json_attributes]) unless config[:json_attributes].empty?
        puts "\n"
        msg_pair("Knife config generated", config[:config_file])
      end

      def retrieve_files(fqdn, files)
        options = Hash.new
        options[:password] = Chef::Config[:ssh_password]
        options[:paranoid] = config[:host_key_verify]
        options[:port] = Chef::Config[:ssh_port] unless Chef::Config[:ssh_port].nil?
        Net::SCP.start(fqdn, Chef::Config[:ssh_user], options) do |scp|
          synch = Array.new
          files.each do |file|
            puts ui.color("Downloading file ", :magenta) << "#{fqdn}:#{file}" << ui.color(" to ", :magenta) << "#{Dir.pwd}" << ui.color(" ...", :magenta)
            synch << scp.download(file, Dir.pwd)
          end
          synch.each { |d| d.wait }
          puts('done')
        end
      rescue => e
        puts ui.error("Downloading some files from the node failed. Error: #{e}")
        exit 1
      end

      def configure_knife(fqdn)
        additional_config = IO.read(config[:config_file])

        configure = Chef::Knife::Configure.new
        configure.config[:defaults] = true
        configure.config[:initial] = true
        configure.config[:node_name] = Etc.getlogin
        configure.config[:client_key] = File.join(File.dirname(config[:config_file]), "#{Etc.getlogin}.pem")
        configure.config[:chef_server_url] = config[:chef_server_url_template].sub(/FQDN/, fqdn)
        configure.config[:admin_client_name] = 'chef-webui'
        configure.config[:admin_client_key] = File.join(Dir.pwd, 'webui.pem')
        configure.config[:validation_client_name] = 'chef-validator'
        configure.config[:validation_key] = File.join(Dir.pwd, 'validation.pem')
        configure.config[:repository] = config[:repository]
        configure.config[:config_file] = config[:config_file]
        # monkey patch Chef::Knife::Configure to not ask anything
        class << configure
          define_method(:ask_user_for_config_path) {} 
          define_method(:ask_user_for_config) do
            @chef_server            = config[:chef_server_url]
            @new_client_name        = config[:node_name]
            @admin_client_name      = config[:admin_client_name]
            @admin_client_key       = config[:admin_client_key]
            @validation_client_name = config[:validation_client_name]
            @validation_key         = config[:validation_key]
            @new_client_key         = config[:client_key]
            @chef_repo              = config[:repository]
          end
        end
        configure.run

        open(config[:config_file], 'a') { |f| f << "\n#{additional_config}\n" }
      end

      def bootstrap_for_node(server,fqdn)
        bootstrap = Chef::Knife::Bootstrap.new
        bootstrap.name_args = [fqdn]
        bootstrap.config[:run_list] = config[:run_list]
        bootstrap.config[:ssh_user] = Chef::Config[:ssh_user] || config[:ssh_user] 
        bootstrap.config[:ssh_port] = Chef::Config[:ssh_port] || config[:ssh_port]
        if Chef::Config[:identity_file].nil? && config[:identity_file].nil? then
          bootstrap.config[:ssh_password] = Chef::Config[:ssh_password] || config[:ssh_password]
        else
          bootstrap.config[:identity_file] = Chef::Config[:identity_file] || config[:identity_file]
        end
        bootstrap.config[:chef_node_name] = config[:chef_node_name] || fqdn
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
