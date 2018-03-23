#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'sqlite3'

def normalize_date(date)
  Time.new(*date.split('-')).to_i
end

def sql_placeholders(array)
  (['?'] * array.length).join(',')
end

def stale?(origin, symbols)
  last_updates = DB.execute("select timestamp from rates where base=? AND symbol IN (#{sql_placeholders(symbols)})", origin, symbols).flatten
  last_updates.count < symbols.count || last_updates.any? { |i| (Date.today.to_time.to_i - DAY_IN_SECONDS * 2) > i.to_i }
end

def grab_rates(origin, symbols)
  return unless stale?(origin, symbols)

  data = JSON.parse(Net::HTTP.get(URI("https://api.fixer.io/latest?symbols=#{symbols}&base=#{origin}")))
  base = data['base']

  print "Updated rates for #{origin.upcase}: "
  data['rates'].each do |k, v|
    print "#{k} "
    DB.execute('select base, symbol, timestamp from rates where base=? AND symbol=?', base, k)
    DB.execute('insert or ignore into rates(base, symbol, value, timestamp) values(?, ?, ?, ?)',
               base, k, v, normalize_date(data['date']))
  end
  print "\n"
end

DAY_IN_SECONDS = 86_400

symbols = %w[JPY]
origin = 'CAD'
year = Time.now.year

DB = SQLite3::Database.new('budget.sqlite')

DB.execute("create table if not exists rates(
  id integer PRIMARY KEY,
  base text NOT NULL,
  symbol text NOT NULL,
  value text NOT NULL,
  timestamp integer NOT NULL,
  constraint unq unique (base, symbol, timestamp)
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

system 'clear'
puts "Welcome back!\nFormat expected: <VALUE> <CURRENCY> <DESCRIPTION>"
loop do
  print '>> '
  case gets.chomp
  when 'b'
    puts origin
  when /^b (\w{3})\z/
    origin = Regexp.last_match(1)
    grab_rates(origin.upcase!, symbols)
  when 's'
    puts symbols
  when /^s (\w{3}\ ?\w{3}?)+\z/
    symbols += Regexp.last_match(1).split.map(&:upcase!)
    grab_rates(origin, symbols)
  when /^(\+?)(\d+\.?\d*)(\ [a-zA-Z]{3})?(\ .*)?\z/
    deposit = !Regexp.last_match(1).empty?
    value  = Regexp.last_match(2)
    symbol = Regexp.last_match(3)&.strip
    symbol.upcase! if symbol
    desc = Regexp.last_match(4)&.strip

    grab_rates(origin, [symbol]) unless symbol.nil? || (symbols + [origin]).include?(symbol)
    ratio = symbol ? DB.execute('select value from rates where base=? AND symbol=?', origin, symbol).flatten[0].to_f : 1
    converted = value.to_f / ratio

    converted *= -1 if deposit
    next if converted == Float::INFINITY

    DB.execute('insert into line_items(real_value, converted_value, description, base, symbol, ratio, timestamp)'\
               ' values(?, ?, ?, ?, ?, ?, ?)', value, converted, desc, origin, symbol || origin, ratio, Time.now.to_i)
    puts "Captured for #{format('%.2f', converted)} #{origin}."
  when 'y'
    puts year
  when /^y (\d{4})\z/
    year = Regexp.last_match(1)
  when 't'
    records = DB.execute('select timestamp, converted_value, description, base, symbol, ratio'\
                         ' from line_items'\
                         " where strftime('%Y', datetime(timestamp, 'unixepoch')) = strftime('%Y', 'now')")
    totals = DB.execute('select base, sum(converted_value) as sub_total'\
                        ' from line_items'\
                        ' group by base')
    next if records.empty?

    records.each do |record|
      time, value, desc, base, symbol, ratio = *record
      puts "#{Time.at(time).strftime('%Y %b %d')} | "\
           "#{format('%.2f', value)} | "\
           "#{symbol}->#{base}@#{format('%.2f', ratio.to_f**-1)} "\
           "#{'- ' + desc if desc}"
    end
    puts
    totals.each do |total|
      puts "#{year} #{total.first} TOTAL: #{format('%.2f', total.last)}"
    end
  when /^t (.+)\z/
    month = Regexp.last_match(1).capitalize
    month = Date::MONTHNAMES.index(month) || Date::ABBR_MONTHNAMES.index(month) || month.to_i

    records = DB.execute('select timestamp, converted_value, description, base, symbol, ratio'\
                         ' from line_items'\
                         " where strftime('%m', datetime(timestamp, 'unixepoch')) = ?",
                         month.to_s.rjust(2, '0'))
    totals = DB.execute('select base, sum(converted_value) as sub_total'\
                        ' from line_items'\
                        ' group by base')
    next if records.empty?

    records.each do |record|
      time, value, desc, base, symbol, ratio = *record
      puts "#{Time.at(time).strftime('%Y %b %d')} | "\
           "#{format('%.2f', value)} | "\
           "#{symbol}->#{base}@#{format('%.2f', ratio.to_f**-1)} "\
           "#{'- ' + desc if desc}"
    end
    puts
    totals.each do |total|
      puts "#{Date::MONTHNAMES[month]} #{total.first} TOTAL: #{format('%.2f', total.last)}"
    end
  when 'r'
    DB.execute('select base, symbol, value from rates').each do |rate|
      puts "#{rate[1]}->#{rate[0]}@#{format('%.2f', rate[2].to_f**-1)}"
    end
  when /.*exit.*/
    system 'clear'
    exit
  else
    puts 'Usage:'
    puts "\tb\t\t\t\t- Inspect base currency"
    puts "\tb (\\w{3})\t\t\t- Set base curreny"
    puts "\ts\t\t\t\t- Inspect avaiable conversion targets"
    puts "\ts (\\w{3}\\ ?\\w{3}?)+\t\t- Add conversion targets"
    puts "\tr\t\t\t\t- Inspect all stored rates"
    puts "\t<VALUE> <CURRENCY> <NOTE>\t- Add item:"
    puts "\t\t\t\t\t  <VALUE> required"
    puts "\t\t\t\t\t  <CURRENCY> optional, defaults to base"
    puts "\t\t\t\t\t  <DESCRIPTION> optional"
    puts "\ty\t\t\t\t- Inspect year, used for totals"
    puts "\ty (\\d{4})\t\t\t- Set year used for totals"
    puts "\tt\t\t\t\t- Calculate totals for year"
    puts "\tt (.+)\t\t\t\t- Calculate totals for month in year"
    puts "\texit\t\t\t\t"
  end
end
