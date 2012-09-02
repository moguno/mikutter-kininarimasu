# -*- coding: utf-8 -*-
  
require 'date'

# 検索クラス
class Chitanda
  attr_reader :last_fetch_time,:keywords


  # コンストラクタ
  def initialize(service, keywords)
    @service = service
    @keywords = keywords
    @result_queue = Array.new()
    @queue_lock = Mutex.new()
    @last_result_time = nil
    @last_fetch_time = Time.now
  end


  # 日時文字列をパースする
  def parse_time(str)
    begin
      Time.parse(str)
    rescue
      nil
    end
  end


  # 検索結果を取り出す
  def fetch()
    msg = nil

    @queue_lock.synchronize {
      msg = @result_queue.shift
    }

    if msg != nil then
      @last_fetch_time = Time.now
    end

    return msg
  end


  # 検索する
  def search()
    query_keyword = @keywords.join("+OR+")

    # p query_keyword
  
    if query_keyword.empty? then
      return
    end
  
    params = {}
  
    params[:q] = query_keyword + "+-rt+-via"
    params[:rpp] = "100"
  
    if query_keyword.empty? then
      return
    end
  
    params = {}
  
    params[:q] = query_keyword + "+-rt+-via"
    params[:rpp] = "100"
  
    if UserConfig[:interest_japanese] then
      params[:lang] = "ja"
    end

    @service.search(params).next{ |res| 
      begin
        res = res.select { |es|
          result_tmp = false

          tim = parse_time(es[:created_at]) 

          if es[:message] =~ /^RT / then
            result_tmp = false
          elsif $last_time == nil then
            result_tmp = true
          elsif tim != nil && $last_time < tim then
            result_tmp = true
          else
            result_tmp = false
          end

          # 重たい検索を行う
          if result_tmp then
            if keywords.inject(false) {|result, key| result | (/#{key}/i =~ es[:message])} then
              true
            else
              false
            end 
          else
            false
          end
        }
  
        if res.size == 0 then
          next
        end
  
        res.each { |es| 
          tim = parse_time(es[:created_at])
  
          if tim != nil && (@last_result_time == nil || @last_result_time < tim) then
            @last_result_time = tim
          end
        }
  
        # p "new message:" + res.size.to_s
        # p "last time:" + $last_time.to_s
  
        @queue_lock.synchronize {
          @result_queue.concat(res.reverse)
        }
      rescue => e
        puts e
        puts e.backtrace
      end
    }
  end
end
  

Plugin.create :kininarimasu do 
  
  # コンフィグの初期化
  UserConfig[:interest_keyword1] ||= ""
  UserConfig[:interest_keyword2] ||= ""
  UserConfig[:interest_keyword3] ||= ""
  UserConfig[:interest_keyword4] ||= ""
  UserConfig[:interest_keyword5] ||= ""
  UserConfig[:interest_japanese] ||= true
  UserConfig[:interest_period] ||= 60
  UserConfig[:interest_insert_period] ||= 3
  UserConfig[:interest_prefix] ||= ""
  UserConfig[:interest_background_color] ||= [65535, 65535, 65535]
  UserConfig[:interest_custom_style] ||= false
  UserConfig[:interest_font_face] ||= 'Sans 10'
  UserConfig[:interest_font_color] ||= [0, 0, 0]

 

  # グローバル変数の初期化
  $chitandas = []


  # 設定画面
  settings "わたし、気になります" do
    settings "検索ワード" do
      input("", :interest_keyword1)
      input("", :interest_keyword2)
      input("", :interest_keyword3)
      input("", :interest_keyword4)
      input("", :interest_keyword5)
    end
 
    boolean("日本語のツイートのみ", :interest_japanese)
    adjustment("ポーリング間隔（秒）", :interest_period, 1, 6000)
    adjustment("混ぜ込み間隔（秒）", :interest_insert_period, 1, 600)
    input("プレフィックス", :interest_prefix)

    settings "カスタムスタイル" do
      boolean("カスタムスタイルを使う", :interest_custom_style)
      fontcolor("フォント", :interest_font_face, :interest_font_color)
      color("背景色", :interest_background_color)
    end
  end 


  # キーワードのリストを取得
  def get_keywords()
    [:interest_keyword1, :interest_keyword2, :interest_keyword3, :interest_keyword4, :interest_keyword5]
    .map{ |key| UserConfig[key] }
  end


  # カスタムスタイルを選択する
  def choice_style(message, key, default)
    if !UserConfig[:interest_custom_style] then
      default
    elsif message[:kininarimasu] then
      UserConfig[key]
    else
      default
    end
  end


  # 検索用ループ
  def search_loop(service)
    Reserver.new(UserConfig[:interest_period]){
      keywords = search_keyword(service) 
      search_loop service
    } 
  end
  
  
  # 混ぜ込みループ
  def insert_loop(service)
    Reserver.new(UserConfig[:interest_insert_period]){
      begin
        fetch_order = $chitandas.select(){ |a| a != nil }.sort() { |a, b|
          a.last_fetch_time <=> b.last_fetch_time
        }

        msg = nil

        fetch_order.each { |chitanda|
          msg = chitanda.fetch()

          if msg != nil then
            break
          end
        }

        if msg != nil then

          msg[:created] = Time.now
          msg[:kininarimasu] = true
  
          if !UserConfig[:interest_prefix].empty? then
            msg[:message] = UserConfig[:interest_prefix] + " " + msg[:message]
          end
  
          msg.user[:created] ||= Time.now

          # タイムラインに登録
          if defined?(timeline)
            timeline(:home_timeline) << [msg]
          else
            Plugin.call(:update, service, [msg])
          end

          # puts "last message :" + $result_queue.size.to_s
        end

      rescue => e
        puts e
        puts e.backtrace

      ensure
        insert_loop service

      end
    } 
  end
  

  # 検索
  def search_keyword(service)
    begin
      keywords = get_keywords() 

      (0..keywords.length - 1).each { |i|
        if keywords[i].empty? then
          $chitandas[i] = nil
        elsif ($chitandas[i] == nil) || ($chitandas[i].keywords <=> [keywords[i]]) != 0 then
          $chitandas << Chitanda.new(service, [keywords[i]])
        end
      }

      $chitandas.select { |a| a != nil }.each { |chitanda|
        chitanda.search()
      }
    rescue => e
      puts e
      puts e.backtrace
    end
  end


  # 起動時処理
  on_boot do |service|
    search_loop service
    insert_loop service
  end


  # 背景色決定
  filter_message_background_color do |message, color|
    begin
      color = choice_style(message.message, :interest_background_color, color)

      [message, color]

    rescue => e
      puts e
      puts e.backtrace
    end
  end


  # フォント色決定
  filter_message_font_color do |message, color|
    begin
      color = choice_style(message.message, :interest_font_color, color)

      [message, color]

    rescue => e
      puts e
      puts e.backtrace
    end
  end


  # フォント決定
  filter_message_font do |message, font|
    begin
      font = choice_style(message.message, :interest_font_face, font)

      [message, font]

    rescue => e
      puts e
      puts e.backtrace
    end
  end
end
