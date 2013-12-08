#!/usr/bin/ruby

require 'sinatra'
require 'sequel'
require 'bcrypt'
require 'json'

DB = Sequel.connect('sqlite://db')

DB.create_table?(:users) do
  primary_key :user_id

  String      :user_name
  String      :user_password
end

DB.create_table?(:lists) do
  primary_key :list_id

  String      :list_name
end

DB.create_table?(:payments) do
  primary_key :payment_id

  foreign_key :payment_user, :users
  foreign_key :payment_list, :lists

  String      :payment_what
  Float       :payment_sum
  Integer     :payment_date
end

DB.create_table?(:debts) do
  primary_key :debt_id

  foreign_key :debt_from, :users
  foreign_key :debt_to,   :users

  Float       :debt_amount
  Integer     :debt_date #actually just Year + month to integer
  Bool        :debt_paid
end

Users    = DB[:users]
Lists    = DB[:lists]
Payments = DB[:payments]
Debts    = DB[:debts]

module Sinatra
module Db
  def new_user(name, password)
    crypted = BCrypt::Password.create(password)

    Users.insert(
      :user_name     => name,
      :user_password => crypted
    )
  end

  def new_list(name)
    Lists.insert(:list_name => name)
  end

  def get_default_list
    Lists.first[:list_id]
  end

  def get_distinct_users(list, start_t, end_t)
    Payments.select(:payment_user).where(
      :payment_date => (start_t .. end_t),
      :payment_list => list
    ).distinct
  end

  def new_payment(user, what, sum, list)
    Payments.insert(
      :payment_user => user,
      :payment_what => what,
      :payment_sum  => sum,
      :payment_date => Time.now.to_i,
      :payment_list => list)
  end

  def get_user_name(user_id)
    Users.select.where(:user_id => user_id).first[:user_name]
  end

  def get_payments(list, start_t, end_t)
    Payments.join(:users, :user_id => :payment_user).
      where(:payment_date => (start_t .. end_t), :payment_list => list)
  end

  def delete_payment(pid)
    p = Payments.select.where(:payment_id => pid)

    raise 'No such payment' if p.count.zero?
    raise 'Cannot delete this payment (it\'s not yours)' if
      not p.first[:payment_user].to_i.eql?(session[:user][:id])

    p.delete
  end

  def set_paid_debt(debt_id)
    Debts.select.where(:debt_id => debt_id).update(:debt_paid => true)
  end

  def saved_debts_table(start_t)
    debts = Debts.select.where(:debt_date => start_t)
    if debts.count.zero?
      table = nil
    else
      table = []
      debts.each do |d|
        table << {
          :debt_id => d[:debt_id],
          :from    => d[:debt_from],
          :to      => d[:debt_to],
          :what    => d[:debt_amount],
          :paid    => d[:debt_paid]
        }
      end
    end

    table
  end

  def store_debts_table(start_t, debts)
    return if debts.nil?

    debts.each do |d|
      d[:debt_id] = Debts.insert(
        :debt_from   => d[:from],
        :debt_to     => d[:to],
        :debt_date   => start_t,
        :debt_amount => d[:what],
        :debt_paid   => false)
    end
  end
end

module DebtMatrix
  def calc_debtmatrix(exp, debts = [])
    stat = {}

    exp = exp.reject { |k,v| v.zero? }
    return debts if exp.size == 1

    avg = exp.reduce(0) { |sum, (_, v)| sum + v }.to_f / exp.size
    exp.each { |k, v| stat[k] = v - avg }

    min_recv, max_recv = [stat.min_by(&:last), stat.max_by(&:last)]

    exp[max_recv[0]] -= min_recv[1].abs
    exp[min_recv[0]] = 0

    debts << {
      :from => min_recv[0],
      :to   => max_recv[0],
      :what => min_recv[1].abs.round(2)
    }

    calc_debtmatrix(exp, debts)
  end
end

module Validate
  def validate name, param
    response = {
      :status => 'error',
      :msg    => "Please specify #{name}"
    }

    halt(response.to_json) if params[param].nil? or params[param].empty?

    params[param]
  end
end

module View
  def build_lists_list(default=1)
    return nil if Lists.count.eql? 1

    list = ''

    Lists.each do |l|
      list += "<option value='#{l[:list_id]}'" +
        "#{" selected='selected'" if
          default.to_i == l[:list_id]} >#{l[:list_name]}</option>"
    end

    list
  end

  def build_period_list(curr)
    list = ''

    DB["SELECT DISTINCT strftime('%Y %m',payment_date, 'unixepoch') " +
      "AS ym FROM payments ORDER BY ym DESC"].each do |d|
      list += "<option value='#{d[:ym]}'"
      list += " selected" if d[:ym].eql? curr
      list += ">#{d[:ym]}</option>"
    end

    list
  end

  def build_summary_table(ind_tot, avg_tot)
    summary = ''
    c       = 0

    ind_tot.each do |k,v|
      d = (v - avg_tot).round(2)

      summary += '<tr class=' + (d >= 0 ? 'success' : 'danger' ) + '><td>' + k.to_s +
        '</td><td>' + v.round(2).to_s + '</td><td class=>' + d.to_s + '</td></tr>'

      c = c + 1
    end

    summary
  end

  def build_payments_table(payments)
    table = ''
    c     = 0

    payments.each do |p|
      table += '<tr' + (c.even? ? ' class=alt' : '') +
        '><td>' + Time.at(p[:payment_date]).strftime('%d %b, %H:%M') +
        '</td><td>' + p[:user_name] + '</td><td>' + p[:payment_what] +
        '</td><td>' + p[:payment_sum].to_s + '</td>' +
        '</td><td><a href=/delete?pid=' + p[:payment_id].to_s + '&uid=' +
        p[:payment_user].to_s + '&lid=' + p[:payment_list].to_s + '>X</a></td></tr>'

      c = c + 1
    end

    table
  end

  def build_payme_table(debts, last_period)
    table = ''
    c     = 0

    debts.each do |d|
      table += '<tr' + (c.even? ? ' class=alt' : '') + '><td>' +
        get_user_name(d[:from]) + '</td><td>' +
        d[:what].to_s + '</td><td>' +
        get_user_name(d[:to]) + '</td>'

      if not last_period
        table += '<td id="debt_' + d[:debt_id].to_s + '">'
        if d[:paid]
          table += '<span style="color: #24de44" class="glyphicon glyphicon-ok"></span>'
        else
          if session[:user][:id] == d[:to]
            table += ' <button type="button" class="btn btn-danger btn-xs" onClick="set_paid(' + d[:debt_id].to_s + ')">set paid.</button></td>'
          else
            table += '<span style="color: #fe2444" class="glyphicon glyphicon-remove"></span>'
          end
        end
        table += "</td>"
      end

      table += '</tr>'
      c = c + 1
    end

    table
  end

  def menu_item(link, name)
    active = (request.path_info == link ? "class=\"active\"" : "")
    "<li #{active}><a href=\"#{link}\">#{name}</a></li>"
  end
end

module Auth
  def authenticate!(name, password)
    user = Users.where(:user_name => name)

    if user.count.nonzero? and BCrypt::Password.new(user.first[:user_password]) == password
      session[:user] = {
        :name => name,
        :id   => user.first[:user_id]
      }
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
  set :bind, '0.0.0.0'
  enable :sessions
end

before do
  pass if request.path_info.split('?')[0].match(/^\/first_config|^\/auth/)

  redirect '/first_config' if Users.count.zero? #which means no admin user.
  redirect '/auth' if session[:user].nil?
end

before '/admin/*' do
  @fail_erb = {
    :error => 'Admin area.',
    :msg   => "You are not admin"
  }

  halt erb(:fail) if session[:user][:id] != 1
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
  name           = validate('first user name', :name)
  password       = validate('first user password', :password)
  list           = validate('first list', :list)

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
  name     = validate('username', :name)
  password = validate('password', :password)

  session[:user] = authenticate!(name, password)

  if authenticated?
    redirect '/'
  else
    @fail_erb = {
      :error => 'Wrong passphrase',
      :msg   => "But you can try <a href=/auth>again</a>"
    }

    halt erb(:fail)
  end
end

get '/admin/new_user' do
  erb :new_user
end

post '/admin/new_user' do
  name     = validate('name',  :name)
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
  list     = params[:list] || Lists.first[:list_id]

  ind_tot  = Hash.new(0) # per user total
  tot      = 0 # global total

  period   = params["period"] || Time.now.strftime("%Y %m")
  year     = period[0..3].to_i
  month    = period[5..6].to_i

  start_t  = Time.mktime(year, month).to_i
  end_t    = (month.eql?(12) ? Time.mktime(year + 1) : Time.mktime(year, month + 1)).to_i

  payments = get_payments(list, start_t, end_t)

  if payments.count.zero?
    halt(erb(:no_payments))
  end

  last_period = Time.now.strftime("%Y %m").eql? period
  debtmatrix  = saved_debts_table(start_t)

  if debtmatrix.nil?
    if not payments.count.zero?
      users_n  = get_distinct_users(list, start_t, end_t).count

      payments.each do |p|
        ind_tot[p[:user_id]] += p[:payment_sum].to_f.round(2)
        tot                  += p[:payment_sum].to_f.round(2)
      end

      debtmatrix = calc_debtmatrix(ind_tot)
      avg_tot    = (tot / users_n).round(2)
    end
  end

  store_debts_table(start_t, debtmatrix) if not last_period and saved_debts_table(start_t).nil?

  @payments_erb = {
    :lists_list     => build_lists_list(list),
    :period_list    => build_period_list(period),
    :summary_table  => build_summary_table(ind_tot, avg_tot),
    :payments_table => build_payments_table(payments),
    :payme_table    => build_payme_table(debtmatrix, last_period),
    :last_period    => last_period
  }

  erb :payments
end

post '/' do
  what = validate('what', :what)
  sum  = validate('sum', :sum).gsub(',', '.').to_f
  list = params[:list] || get_default_list()

  if sum.to_i < 0
    response = {
      :status => 'error',
      :msg    => 'Negative sum.<br>Doesn\'t make sense.'
    }

    halt response.to_json
  end

  new_payment(session[:user][:id], what, sum, list)

  response = {
    :status => "ok",
    :msg    => "Successfully added #{session[:user][:name]}'s payment:<br>#{sum}€ for #{what}"
  }

  response.to_json
end

post '/set_paid' do
  debt_id = params[:debt_id]
  set_paid_debt(debt_id)

  response = { :status => "ok" }
  response.to_json
end

get '/delete' do
  pid = validate('payement id', :pid)

  begin
    delete_payment(pid).eql?(-1)
  rescue Exception => e
    @fail_erb = {
      :error => 'Fail deleting payment.',
      :msg   => e.message + '<br>Go <a href=/>back</a>'
    }

    halt erb(:fail)
  end

  redirect '/'
end

get '/logout' do
  session.clear
  redirect '/auth'
end

