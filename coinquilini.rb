#!/usr/bin/ruby

require 'sinatra'
require 'sequel'

DB = Sequel.connect('sqlite://db')

DB.create_table?(:users) do
  primary_key	:id

  String	:name
	String	:password
end

DB.create_table?(:lists) do
  primary_key	:id

  String	:name
end

DB.create_table?(:payments) do
  primary_key	:id

  foreign_key	:user, :users
  foreign_key	:list, :lists

  String	:what
  Float		:sum
  Integer	:date
end

Users = DB[:users]
Lists = DB[:lists]
Payments = DB[:payments]

module Sinatra
module Db
	def new_user(name, password)
		Users.insert(:name => name, :password => password)
	end

	def new_list(name)
		Lists.insert(:name => name)
	end

	def get_distinct_users
		Payments.select(:user).distinct
	end

	def new_payment(user, what, sum, list)
		Payments.insert(:user => user, :what => what, :sum => sum, :date => Time.now.to_i, :list => list)
	end

	def get_payments(list, start_t, end_t)
		 Payments.join(:users, :id => :user).where(:date => (start_t .. end_t), :list => list)
	end
end

module DebtMatrix
	def calc_debtmatrix exp, debts = []
		stat = {}

		exp = exp.reject { |k,v| v.zero? }
		return debts if exp.size == 1

		avg = exp.reduce(0) { |sum, (_, v)| sum + v }.to_f / exp.size
		exp.each { |k, v| stat[k] = v - avg }

		min_recv, max_recv = [stat.min_by(&:last), stat.max_by(&:last)]

		exp[max_recv[0]] -= min_recv[1].abs
		exp[min_recv[0]] = 0

		debts << { :from => min_recv[0], :to => max_recv[0], :what => min_recv[1].abs.round(2)}

		calc_debtmatrix exp, debts
	end
end

module Validate
	def validate name, param
		@fail_erb = {
			:error => 'Something\'s missing.',
			:msg	=> "Please specify #{name}"
		}

		halt erb(:fail) if params[param].nil? or params[param].empty?

		params[param]
	end
end

module View
	def build_lists_list(default=1)
		list = ''

		Lists.each do |l|
			list += "<option value='#{l[:id]}'#{" selected='selected'" if default.to_i == l[:id]} >#{l[:name]}</option>"
		end

		list
	end

	def build_period_list
		list = ''

		DB["SELECT DISTINCT strftime('%Y %m',date, 'unixepoch') AS ym FROM payments"].each do |d|
			list += "<option value='#{d[:ym]}'>#{d[:ym]}</option>"
		end

		list
	end

	def build_summary_table(ind_tot, avg_tot)
		summary	= ''
		c = 0

		ind_tot.each do |k,v|
			d = (v - avg_tot).round(2)

			summary += '<tr ' + (c.even? ? ' class=alt' : '') + '><td>' + k.to_s +
				'</td><td>' + v.round(2).to_s + '</td><td class=' +
				(d >= 0 ? 'green' : 'red') + '>' + d.to_s + '</td></tr>'

			c = c + 1
		end

		summary
	end

	def build_payments_table(payments)
		table = ''
		c = 0

		payments.each do |p|
			table += '<tr' + (c.even? ? ' class=alt' : '') +
				'><td>' + Time.at(p[:date]).strftime('%d %b, %H:%M') +
				'</td><td>' + p[:name] + '</td><td>' + p[:what] +
				'</td><td>' + p[:sum].to_s + '<td></td></tr>'

			c = c + 1
		end

		table
	end

	def build_payme_table(debts)
		table = ''
		c = 0

		debts.each do |d|
			table += '<tr' + (c.even? ? ' class=alt' : '') +
				'><td>' + d[:from] +
				'</td><td>' + d[:what].to_s + '</td><td>' + d[:to] + '<td></td></tr>'

			c = c + 1

		end

		table
	end
end

module Auth
	def authenticate!(name, password)
		res = Users.where(:name => name, :password => password)
		if res.count.nonzero?
			session[:user] = {:name => name, :id => res.first[:id]}
		end
	end

	def authenticated?
		not session[:user].nil?
	end
end
end

configure do
	helpers Sinatra::Db
	helpers Sinatra::DebtMatrix
	helpers Sinatra::Validate
	helpers Sinatra::View
	helpers Sinatra::Auth

	set :server, :puma
	set :port, 1234
	enable :sessions
end

before do
	pass if request.path_info.split('?')[0].match(/^\/first_config|^\/auth/)

	#todo check admin
	redirect '/first_config' if Users.count.zero? #which means no admin user.
	redirect '/auth' if session[:user].nil?
end

get '/' do
	@pay_form_erb = { :lists_list => build_lists_list }
	erb :pay_form
end

get '/first_config' do
	erb :first_config
end

post '/first_config' do
	admin_password = validate('admin password', :admin_password)
	name = validate('first user name', :name)
	password = validate('first user password', :password)
	list = validate('first list', :list)

	new_user('admin', admin_password)
	new_user(name, password)

	new_list(list)

	redirect '/auth'
end

get '/auth' do
	session.clear
	erb :auth
end

post '/auth' do
	name = validate('username', :name)
	password = validate('password', :password)

	session[:user] = authenticate!(name, password)

	if authenticated?
		redirect '/'
	else
		@fail_erb = {
			:error => 'Wrong passphrase',
			:msg	=> "But you can try <a href=/auth>again</a>"
		}

		halt erb(:fail)
	end
end

get '/admin/new_user' do
	erb :new_user
end

post '/admin/new_user' do
	name = validate('name',  :name)
	password = validate('password',  :password)

	new_user(name, password)

	redirect '/'
end

get '/admin/new_list' do
	erb :new_list
end

post '/admin/new_list' do
	name = validate('list name',  :name)

	new_list(name)

	redirect '/'
end

get '/payments' do
	list = params[:list] || Lists.first[:id]

	ind_tot	= Hash.new(0) # per user total
	tot	= 0 # global total

	period	= params["period"] || Time.now.strftime("%Y %m")
	year	= period[0..3].to_i
	month	= period[5..6].to_i
	users_n	= get_distinct_users.count

	start_t = Time.mktime(year, month).to_i
	end_t	= (month.eql?(12) ? Time.mktime(year + 1) :
		  Time.mktime(year, month + 1)).to_i

	payments = get_payments(list, start_t, end_t)
	payments.each do |p|
		ind_tot[p[:name]] += p[:sum].to_f.round(2)
		tot += p[:sum].to_f.round 2
	end

	debtmatrix = calc_debtmatrix ind_tot

	avg_tot = (tot / users_n).round(2)

	@payments_erb = {
		:lists_list => build_lists_list(list),
		:period_list	=> build_period_list,
		:summary_table	=> build_summary_table(ind_tot, avg_tot),
		:payments_table	=> build_payments_table(payments),
		:payme_table	=> build_payme_table(debtmatrix)
	}

	erb :payments
end

post '/' do
	list = validate('list', :list)
	what	= validate('what', :what)
	sum	= validate('sum', :sum).gsub(',', '.')

	new_payment(session[:user][:id], what, sum, list)

	redirect "/payments?list=#{list}"
end

get '/logout' do
	session.clear
	redirect '/auth'
end

