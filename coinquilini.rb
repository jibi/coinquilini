#!/usr/bin/ruby
#
require 'sinatra'
require 'sequel'

DB = Sequel.connect('sqlite://db')

DB.create_table?(:users) do
  primary_key	:id

  String	:name
end

DB.create_table?(:payments) do
  primary_key	:id
  foreign_key	:who, :users

  String	:what
  Float		:how
  Integer	:date
end

Users = DB[:users]
Payments = DB[:payments]

module Sinatra
module Validate
	def validate name, param
		halt erb(:fail, {:locals => { 
		  :error => 'Something\'s missing.',
		  :msg => "Please specify #{name}" }}) if 
		  params[param].nil? or params[param].empty?
	end
end
end

configure do
	helpers Sinatra::Validate
end

get '/' do
	erb :pay_form
end

get '/show' do

end

post '/' do
	validate 'who', :who
	validate 'what', :what
	validate 'how', :how

	Payments.insert(
		:who	=> params[:who], 
		:what	=> params[:what], 
		:how	=> params[:how].gsub(',', '.'),
		:date	=> Time.now.to_i
	)

	redirect '/show'
end
