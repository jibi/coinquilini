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
module Db
	def new_user(who)
		Users.insert(:name => who)
	end

	def get_distinct_users
		Payments.select(:who).distinct
	end

	def new_payment(who, what, how)
		Payments.insert(:who => who, :what	=> what, :how => how, :date => Time.now.to_i)
	end

	def get_payments(start_t, end_t)
		Payments.join(:users, :id => :who).where(:date => (start_t .. end_t))
	end
end

module DebtMatrix
	def calc_debtmatrix exp, debts = []
		stat = {}

		exp = exp.reject { |k,v| v.zero? }
		return debts if exp.size == 1

		avg = exp.reduce(0) { |sum, (_k, v)| sum + v }.to_f / exp.size
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
				'</td><td>' + p[:how].to_s + '<td></td></tr>'

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
end

configure do
	helpers Sinatra::Db
	helpers Sinatra::DebtMatrix
	helpers Sinatra::Validate
	helpers Sinatra::View

	set :server, :puma
end

before do
	pass if request.path_info.split('?')[0] == '/new_user'
	redirect '/new_user?none=y' if Users.count.zero?
end

get '/' do
	erb :pay_form
end

get '/new_user' do
	first = (params['none'] == 'y' ? true : false)

	@new_user_erb = { :first => first }

	erb :new_user
end

post '/new_user' do
	who = validate('who',  :who)

	new_user(who)

	redirect '/'
end

get '/show' do

	ind_tot	= Hash.new(0) # per user total
	tot	= 0 # global total

	period	= params["period"] || Time.now.strftime("%Y %m")
	year	= period[0..3].to_i
	month	= period[5..6].to_i
	users_n	= get_distinct_users.count

	start_t = Time.mktime(year, month).to_i
	end_t	= (month.eql?(12) ? Time.mktime(year + 1) :
		  Time.mktime(year, month + 1)).to_i

	payments = get_payments(start_t, end_t)
	payments.each do |p|
		ind_tot[p[:name]] += p[:how].to_f.round(2)
		tot += p[:how].to_f.round 2
	end

	debtmatrix = calc_debtmatrix ind_tot

	avg_tot = (tot / users_n).round(2)

	@list_erb = {
		:period_list	=> build_period_list,
		:summary_table	=> build_summary_table(ind_tot, avg_tot),
		:payments_table	=> build_payments_table(payments),
		:payme_table	=> build_payme_table(debtmatrix)
	}

	erb :list
end

post '/' do
	who	= validate('who', :who)
	what	= validate('what', :what)
	how	= validate('how', :how).gsub(',', '.')

	new_payment(who,what,how)

	redirect '/show'
end
