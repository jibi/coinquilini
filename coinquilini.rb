#!/usr/bin/ruby

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

		  params[param]
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
	ind_tot	= Hash.new(0)
	tot	= 0

	period	= params["period"] || Time.now.strftime("%Y %m")
	year	= period[0..3].to_i
	month	= period[5..6].to_i
	users_n	= Users.count

	start_t = Time.mktime(year, month).to_i
	end_t	= (month.eql?(12) ? Time.mktime(year + 1) :
		  Time.mktime(year, month + 1)).to_i

	payments = Payments.join(:users, :id => :who).where(:date => (start_t .. end_t))

	payments.each do |p|
		ind_tot[p[:name]] += p[:how].to_f.round 2
		tot += p[:how].to_f.round 2
	end

	avg_tot = (tot / users_n).round 2 if users_n.nonzero?

	erb :list, {:locals => { :ind_tot => ind_tot, :avg_tot => avg_tot,
		:payments => payments }}
end

post '/' do
	Payments.insert(
		:who	=> validate('who',  :who), 
		:what	=> validate('what', :what), 
		:how	=> validate('how',  :how).gsub(',', '.'),
		:date	=> Time.now.to_i
	)

	redirect '/show'
end

