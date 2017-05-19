class Auth
  require 'listen'

  def initialize file
    @file = file
    Listen.to('.', only: /#{Regexp.quote(file)}/) do |modified|
      refresh
    end.start
    @ids = []
    refresh
  end

  def authenticate user
    if ids.include? user.id
      true
    else
      false
    end
  end

  def ids
    @ids
  end

  def refresh
    puts "Refreshing ids from #{@file}"
    if File.exist?(@file)
      @ids = File.readlines(@file).map(&:to_i)
    else
      @ids = []
    end
    puts "Authorized ids: #{@ids.inspect}"
  end
end


class TimersInThread
  attr_reader :timers

  def initialize resolution_in_secs
    @timers = Timers::Group.new
    Thread.new { timers_loop }
    @resolution_in_secs = resolution_in_secs
  end

  def timers_loop
    loop do
      @timers.wait do
        sleep @resolution_in_secs
      end
    end
  rescue
    puts "#{$!}"
    puts "#{$@}"
    retry
  end
end

class ChatsNotifier
  def initialize bot, file
    @bot = bot
    @chats = Set.new
    @file = file
    refresh
  end

  def refresh
    puts "Loading chats from #{@file}"
    if File.exist?(@file)
      @chats.merge File.readlines(@file).map(&:to_i)
    end
    puts "Chats: #{@chats.inspect}"
  end

  def save
    File.open(@file, 'w+') do |f|
      f.write(@chats.to_a.join("\n"))
    end
  end

  def register_chat id
    @chats << id
    save
  end

  def unregister_chat id
    @chats.delete id
    save
  end

  def send_other current_id, opts
    current_id=nil
    (@chats.to_a - [current_id]).each do |id|
      @bot.api.send_message({chat_id: id}.merge opts)
    end
  end

  def send opts
    @chats.each do |id|
      @bot.api.send_message({chat_id: id}.merge opts)
    end
  end
end
