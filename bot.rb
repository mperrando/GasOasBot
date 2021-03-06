require 'telegram/bot'
require 'telegram/bot/botan' 
require 'timers'
require_relative 'libbot'

SECS = ARGV[0].to_i || 3
AUTH_FILE = ARGV[1] || "auth_ids.txt"
TOKEN = ENV['TELEGRAM_TOKEN'] || '342935347:AAEdo4J_iTubxtXkjduaxmfyqvU-cspicgU'
puts "Timeout for automatic ON is #{SECS} seconds"
puts "Authorized ids file: #{AUTH_FILE}"
puts "Telegram token in use: #{TOKEN}"

class Caps
  class ALL
    def can? what
      true
    end
  end

  class NULL
    def can? what
      false
    end
  end
end

class ShellCommands
  def run name
    raise "File #{name} not found" unless File.exist?(name)
    raise "File #{name} not readable" unless File.readable?(name)
    system "sh #{name}"
  end

  def on
    run './on.sh'
  rescue
    puts "Skipping on: #{$!}"
  end

  def off
    run './off.sh'
  rescue
    puts "Skipping off: #{$!}"
  end
end

class Lights
  def initialize timers, timeout, cmd
    @cmd = cmd
    @timeout = timeout
    @timers = timers
    @my_mutex = Mutex.new
  end

  def turn_on
    @my_mutex.synchronize do
      @cmd.on
      cancel_timer
    end
  end

  def turn_off
    @my_mutex.synchronize do
      @cmd.off
      cancel_timer
      @timer = @timers.after(@timeout) do 
        turn_on
        yield
      end
    end
  end

  def on_in
    @timer && @timer.fires_in
  end

  def cancel_timer
    @timer && @timer.cancel
    @timer = nil
  end
end

class EUnath < RuntimeError; end
@auth = Auth.new AUTH_FILE
@timers = TimersInThread.new 1
@lights = Lights.new @timers.timers, SECS, ShellCommands.new
Telegram::Bot::Client.run(TOKEN) do |bot|
  #bot.enable_botan!('WjrKZsmFeEjMrEVxXekFVb6d-RoDB1sk')

  @notifier = ChatsNotifier.new bot, "chats.txt"

  bot.listen do |message|
    puts message.inspect
    caps = if @auth.authenticate message.from
             Caps::ALL.new
           else
             false
           end
    unless caps
      bot.api.send_message(chat_id: message.chat.id, text: "Utente non autorizzato")
      next
    end
    unless caps.can? message.text
      bot.api.send_message(chat_id: message.chat.id, text: "Comando non autorizzato")
      next
    end
    case message.text
    when /^\/start/
      kb = [
        [
          Telegram::Bot::Types::KeyboardButton.new(text: 'Spegni'),
          Telegram::Bot::Types::KeyboardButton.new(text: 'Accendi'),
        ],
        Telegram::Bot::Types::KeyboardButton.new(text: 'Status'),
      ]
      markup = Telegram::Bot::Types::ReplyKeyboardMarkup.new(keyboard: kb)
      bot.api.send_message(chat_id: message.chat.id, text: 'Benvenuto!', reply_markup: markup)
      @notifier.register_chat message.chat.id
    when /^\/stop/
      @notifier.unregister_chat message.chat.id
      bot.api.send_message(chat_id: message.chat.id, text: 'Bye bye! Per riattivare le notifiche scrivei /start', reply_markup: markup)
    when /^spegni/i
      on_at = "Verranno riaccese alle #{(Time.now + SECS.to_i).strftime '%R'}"
      actor = message.from
      bot.api.send_message(chat_id: message.chat.id, text: "Spengo le luci. #{on_at}.", reply_markup: markup)
      @notifier.send_other(message.chat.id, text: "@#{actor.username} ha spento le luci. #{on_at}.")
      @lights.turn_off do
        @notifier.send_other(message.chat.id, text: "Tempo scaduto: ho riacceso le luci.")
      end
    when /^accendi/i
      actor = message.from
      bot.api.send_message(chat_id: message.chat.id, text: "Accendo le luci.", reply_markup: markup)
      @notifier.send_other(message.chat.id, text: "@#{actor.username} ha acceso le luci.")
      @lights.turn_on
    when /^status/i
      @lights.on_in.tap do |s|
        if s && s > 0
          bot.api.send_message(chat_id: message.chat.id, text: "Riaccensione luci tra #{s.to_i} secondi")
        else
          bot.api.send_message(chat_id: message.chat.id, text: "Nessuna riaccensione programmata")
        end
      end
    else
    end
  end
end
