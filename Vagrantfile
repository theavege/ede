# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |configure|
    configure.vm.define "node" do |node|
        node.vm.box = 'generic/ubuntu2204'
        node.vm.hostname = ENV['PWD'].split('/')[-1]
        node.vm.provider 'libvirt' do |provider|
            provider.memory = "1536"
            provider.cpus = "2"
        end
    end
end
