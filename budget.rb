# frozen_string_literal: true
require 'net/http'
require 'json'
require 'sqlite3'
require 'pry'

def normalize_date(date)
  Time.new(*date.split('-')).to_i
end

def stale?(origin, symbols)
  last_updates = DB.execute('select timestamp from rates where base=? AND symbol=?', origin, symbols).flatten
  last_updates.count != symbols.count || last_updates.any? {|i| (Date.today.to_time.to_i-DAY_IN_SECONDS) > i.to_i }
end

def grab_rates(origin, symbols)
  base_url = "https://api.fixer.io/latest?" \
             "symbols=#{symbols}&" \
             "base=#{origin}"

  if stale?(origin, symbols)
    resp = Net::HTTP.get(URI(base_url))
    data = JSON.parse(resp)

    base    = data["base"]
    date    = data["date"]
    symbols = data["rates"]

    print "Updating rates for #{origin}: "
    symbols.each do |k,v|
      print "#{k} "
      DB.execute('select base, symbol, timestamp from rates where base=? AND symbol=?', base, k)
      DB.execute('insert into rates(base, symbol, value, timestamp) values(?, ?, ?, ?)',
        base, k, v, normalize_date(date))
    end
    print "\n"
  end
end

DAY_IN_SECONDS = 86400

symbols = %w(JPY)
origin = 'CAD'
year = Time.now.year

DB = SQLite3::Database.new('budget.sqlite')

DB.execute("create table if not exists rates(
  id integer PRIMARY KEY,
  base text NOT NULL,
  symbol text NOT NULL,
  value text NOT NULL,
  timestamp integer NOT NULL
)")

DB.execute("create table if not exists line_items(
  id integer PRIMARY KEY,
  real_value real NOT NULL,
  converted_value real NOT NULL,
  description text,
  base text NOT NULL,
  symbol text NOT NULL,
  ratio text NOT NULL,
  timestamp integer NOT NULL
)")

grab_rates(origin, symbols)

threads = []

system 'clear'
puts "Budget for #{year}\nFormat expected: <VALUE> <CURRENCY> <DESCRIPTION>"
loop do
  print '>> '
  case gets.chomp
  when 'b'
    puts origin
  when /^b (.*)/
    origin = Regexp.last_match(1)
    grab_rates(base_url, origin, symbols)
  when 's'
    puts symbols
  when /^s (.*)/
    symbols << Regexp.last_match(1).split
    threads << Thread.new { grab_rates(origin, symbols) }
  when /^(\d+\.?\d*)\s?([a-zA-Z]{3})?\s?(.*)/
    value  = Regexp.last_match(1)
    symbol = Regexp.last_match(2)
    symbol.upcase! if symbol
    desc   = Regexp.last_match(3)

    grab_rates(origin, [symbol]) unless symbol.nil? || (symbols+[origin]).include?(symbol)
    ratio = symbol ? DB.execute("select value from rates where base=? AND symbol=?", origin, symbol).flatten[0].to_f : 1
    converted = value.to_f/ratio

    next if converted == Float::INFINITY

    DB.execute("insert into line_items(real_value, converted_value, description, base, symbol, ratio, timestamp)"\
               " values(?, ?, ?, ?, ?, ?, ?)", value, converted, desc, origin, symbol || origin, ratio, Time.now.to_i)
    puts "Captured for #{sprintf("%.2f", converted)} #{origin}."
  when 'y'
    puts year
  when /^y (\d+)/
    year = Regexp.last_match(1)
  when 't'
    records = DB.execute("select real_value, converted_value, description, base, symbol"\
                         " from line_items"\
                         " where strftime('%Y', datetime(timestamp, 'unixepoch')) = strftime('%Y', 'now')")
    puts records.inject(0) {|sum, record| sum + record[1] }
  when '/^t (\d+)'
    # show totals for month
  when 'exit'
    puts 'Waiting on threads...'
    threads.join
    system 'clear'
    exit
  else
  end
end
