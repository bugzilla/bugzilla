# vim: set ft=ruby sw=2 ts=2:
# -*- mode: ruby -*-

DB_IP        = ENV.fetch "BMO_DB_IP",    '192.168.3.42'
WEB_IP       = ENV.fetch "BMO_WEB_IP",   '192.168.3.43'
GATEWAY_IP   = ENV.fetch "GATEWAY_IP",   '192.168.3.1'
DNS_IP       = ENV.fetch "DNS_IP",       '8.8.8.8'
DB_HOSTNAME  = ENV.fetch "BMO_DB_HOST",  'bmo-db.vm'
WEB_HOSTNAME = ENV.fetch "BMO_WEB_HOST", 'bmo-web.vm'
DB_PORT      = ENV.fetch "BMO_DB_PORT",  2221
WEB_PORT     = ENV.fetch "BMO_WEB_PORT", 2222
DB_MEM       = ENV.fetch "BMO_DB_MEM",   512
WEB_MEM      = ENV.fetch "BMO_WEB_MEM",  2048
DB_CPU       = ENV.fetch "BMO_DB_CPU",   1
WEB_CPU      = ENV.fetch "BMO_WEB_CPU",  2
HYPERV       = ENV.fetch "HYPERV",       0

# this is for centos 6 / el 6
VENDOR_BUNDLE_URL = ENV.fetch "BMO_BUNDLE_URL",
  'https://moz-devservices-bmocartons.s3.amazonaws.com/bmo/vendor.tar.gz'

RSYNC_ARGS = [
  '--verbose',
  '--archive',
  '-z',
  '--copy-links',
  '--exclude=local/',
  '--exclude=data/',
  '--exclude=logs/',
  '--exclude=template_cache/',
  '--exclude=localconfig',
  '--include=.git/'
]

# This is a little weird, but we need to update
require 'json'

Dir.glob(".vagrant/machines/*/*/synced_folders").each do |filename|
  synced_folders = JSON.parse(IO.read(filename))
  synced_folder = synced_folders["rsync"]["/vagrant"]
  dirty = false
  %w( rsync__args args ).each do |key|
    if RSYNC_ARGS != synced_folder[key]
      dirty = true
      synced_folder[key] = RSYNC_ARGS
    end
    if dirty
      puts "Updating #{filename} because it has old rsync args"
      IO.write(filename + ".new", JSON.unparse(synced_folders))
    end
  end
end


# All Vagrant configuration is done below. The '2' in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure('2') do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  config.vm.provision 'main', type: 'ansible_local', run: 'always' do |ansible|
    ansible.playbook = 'vagrant_support/playbook.yml'
    ansible.extra_vars = {
      WEB_IP:            WEB_IP,
      DB_IP:             DB_IP,
      WEB_HOSTNAME:      WEB_HOSTNAME,
      DB_HOSTNAME:       DB_HOSTNAME,
      VENDOR_BUNDLE_URL: VENDOR_BUNDLE_URL,
      GATEWAY_IP:        GATEWAY_IP,
      DNS_IP:            DNS_IP,
      HYPERV:            HYPERV
    }
  end

  if ARGV.include? '--provision-with'
    config.vm.provision 'update', type: 'ansible_local', run: 'never' do |update|
      update.playbook = 'vagrant_support/update.yml'
    end
  end

  config.vm.define 'db' do |db|
    db.vm.box = 'centos/6'

    db.vm.hostname = DB_HOSTNAME
    db.vm.network 'private_network', ip: DB_IP
    db.vm.network 'forwarded_port',
      id: 'ssh',
      host: DB_PORT,
      guest: 22,
      auto_correct: true

    db.vm.synced_folder '.', '/vagrant', type: 'rsync', rsync__args: RSYNC_ARGS

    db.vm.provider "virtualbox" do |v|
      v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      v.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      v.memory = DB_MEM
      v.cpus = DB_CPU
    end

    db.vm.provider 'parallels' do |prl, override|
      override.vm.box = 'parallels/centos-6.8'
      prl.memory = DB_MEM
      prl.cpus = DB_CPU
    end

    db.vm.provider 'vmware_fusion' do |v|
      v.vmx['memsize'] = DB_MEM
      v.vmx['numvcpus'] = DB_CPU
      v.linked_clone = false
    end
  end

  config.vm.define 'web', primary: true do |web|
    # Every Vagrant development environment requires a box. You can search for
    # boxes at https://atlas.hashicorp.com/search.
    web.vm.box = 'centos/6'
    web.vm.hostname = WEB_HOSTNAME

    # Create a private network, which allows host-only access to the machine
    # using a specific IP.
    web.vm.network 'private_network', ip: WEB_IP
    web.vm.network 'forwarded_port',
      id: 'ssh',
      host: WEB_PORT,
      guest: 22,
      auto_correct: true

    web.vm.synced_folder '.', '/vagrant', type: 'rsync', rsync__args: RSYNC_ARGS

    web.vm.provider 'virtualbox' do |v|
      v.memory = WEB_MEM
      v.cpus = WEB_CPU
      v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      v.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
    end

    web.vm.provider 'parallels' do |prl, override|
      override.vm.box = 'parallels/centos-6.8'
      prl.memory = WEB_MEM
      prl.cpus = WEB_CPU
    end

    web.vm.provider 'vmware_fusion' do |v|
      v.vmx['memsize'] = WEB_MEM
      v.vmx['numvcpus'] = WEB_CPU
    end
  end
end
