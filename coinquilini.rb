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

module UserList
	def user_list
		list = '<select name=who>'
		Users.each do |u|
			list += "<option value='#{u[:id]}'>#{u[:name]}</option>"
		end
		list += '</select>'
	end
end

end

configure do
	helpers Sinatra::UserList
end
get '/' do
	erb :pay_form, {:locals => { :user_list => user_list }}
end

get '/show' do

end

post '/' do

	redirect '/show'
end
