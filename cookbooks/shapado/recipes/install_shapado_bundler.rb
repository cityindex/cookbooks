#
# Cookbook Name:: shapado
# Recipe:: install_shapado_bundler
#
#  OpsCode Chef Cookbooks
#  Copyright 2012 CityIndex Ltd.
#
#  This product includes software developed at
#    CityIndex Ltd. (http://www.cityindex.com)
#

# RVM with 1.9.2 (at least) - Use rvm::default w/ ruby name == 1.9.2
#gem update --system (Need RubyGems ~> 1.8)
#apt-get install libqt4-dev uuid-dev
#gem install bundler --no-ri --no-rdoc
#bundle install
#
#cp config/shapado.yml.sample config/shapado.yml
#cp config/mongoid.yml.sample config/mongoid.yml
#cp config/auth_providers.yml.sample config/auth_providers.yml
#
#bundle exec rake bootstrap RAILS_ENV=production

rightscale_marker :begin


node['rvm']['default_ruby'] = 'ruby-1.9.3-p194@shapado'
node['rvm']['gem_package']['rvm_string'] = 'ruby-1.9.2-p180@shapado'

# node[:rvm][:ruby] = "ruby-1.9.2-p180"
node[:unicorn][:version] = "4.1.1"

include_recipe "rvm::gem_package"
include_recipe "nginx::install_from_package"
include_recipe "unicorn::setup_unicorn"

shapado_install_dir = ::File.join(node[:nginx][:content_dir], "shapado")

if(node[:shapado][:recaptcha_enable] == "true" && (node[:shapado][:recaptcha_public_key].empty? || node[:shapado][:recaptcha_private_key].empty?))
  raise "Recaptcha support for shapado was enabled, but the public or private API key was empty"
end

# Gem native extension requirements
%w{libqt4-dev uuid-dev}.each do |p|
  package p
end

bash "Update RubyGems" do
  code <<-EOF
gem update --system
  EOF
end

gem_package "bundler"

git shapado_install_dir do
  repository node[:shapado][:repository]
  revision node[:shapado][:version]
  action :sync
  not_if { ::File.directory?(shapado_install_dir) }
end

# Need to use the current config template from git, rather than using a static one here.

# TODO: Lots of good configuration bits like enabling social networking and google analytics
template ::File.join(shapado_install_dir, "config", "shapado.yml") do
  source "shapado.yml.erb"
  variables(:uri => node[:shapado][:fqdn])
end

bash "Shapado gem bundle install" do
  cwd shapado_install_dir
  code "rvm exec bundle install"
end

bash "Shapado copy config files" do
  cwd shapado_install_dir
  code <<-EOF
cp config/mongoid.yml.sample config/mongoid.yml
cp config/auth_providers.yml.sample config/auth_providers.yml
  EOF
end

bash "Shapado update GeoIP data" do
  cwd shapado_install_dir
  code "script/update_geoip"
end

bash "Shapado bootstrap" do
  cwd shapado_install_dir
  code <<-EOF
if [ ! -f 'bootstrapped' ] ; then
  echo "Bootstrapping shapado one time"
  RAILS_ENV=#{node[:rails][:environment]} bundle exec rake bootstrap
  touch bootstrapped
else
  echo "Shapado has already been boostrapped, skipping the bootstrap command"
fi
# Ignore errors/warnings from rake bootstrap, cause it complains a lot
exit 0
  EOF
end

unicorn_app "shapado" do
  app_name "shapado"
  app_path shapado_install_dir
  cookbook "shapado"
  template "unicorn.rb.erb"
end

nginx_enable_vhost node[:shapado][:fqdn] do
  cookbook "shapado"
  template "nginx.conf.erb"
  fqdn node[:shapado][:fqdn]
  aliases node[:shapado][:aliases]
  shapado_path shapado_install_dir
  create_doc_root false
end

rightscale_marker :end