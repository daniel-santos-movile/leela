#!/usr/bin/env ruby

require "json"
require "bundler"
Bundler.require

require_relative "../../lib/leela_ruby"

def writeln(str)
  $stdout.write str
  $stdout.write "\n"
  $stdout.flush
rescue Errno::EPIPE
  # try_leela may close the pipe without reading it completly
end

def exec_with_connection(with_block, session, conn)
  until $stdin.eof?
    stmt = JSON.parse($stdin.readline)[0]
    begin
      if with_block
        conn.execute(stmt, session["timeout"]) {|row| writeln [row].to_json}
      else
        conn.execute(stmt, session["timeout"]).each {|row| writeln [row].to_json}
      end
    rescue Leela::LeelaError => e
      writeln [[:fail, e.code, e.message]].to_json
    rescue
      writeln [[:fail, -1, 'lib error']].to_json
    end
    writeln "[null]"
  end
end

def run(with_block)
  session = JSON.parse($stdin.readline)
  if with_block
    Leela::Connection.open(session["endpoint"], session["username"], session["secret"]) do |conn|
      exec_with_connection(with_block, session, conn)
    end
  else
    conn = Leela::Connection.new(session["endpoint"], session["username"], session["secret"])
    begin
      exec_with_connection(with_block, session, conn)
    ensure
      conn.close
    end
  end
end

run (ARGV[0] == "stream")
