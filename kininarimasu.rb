# -*- coding: utf-8 -*-
 
require 'date'


# IDからシンボルを作る
def sym(base, id)
  (base + id.to_s).to_sym
end


# 検索クラス
class Chitanda
  attr_reader :last_fetch_time


  # コンストラクタ
  def initialize(service, user_config, id)
    @service = service
    @last_config = Hash.new
    @result_queue = Array.new()
    @queue_lock = Mutex.new()
    @last_result_time = nil
    @last_fetch_time = Time.now
    @user_config = user_config
    @id = id
  end


  # インスタンス毎のコンフィグを読み込む
  def [](key)
    @user_config[sym(key.to_s, @id)]
  end


  # コンフィグの初期化
  def init_user_config()
    @user_config[sym("interest_keyword", @id)] ||= ""
    @user_config[sym("interest_reverse", @id)] ||= false
    @user_config[sym("interest_user_name", @id)] ||= false
    @user_config[sym("interest_past", @id)] ||= 10
    @user_config[sym("interest_japanese", @id)] ||= true
    @user_config[sym("interest_prefix", @id)] ||= ""

    @user_config[sym("interest_custom_style", @id)] ||= false
    @user_config[sym("interest_font_face", @id)] ||=  'Sans 10'
    @user_config[sym("interest_font_color", @id)] ||= [0, 0, 0]
    @user_config[sym("interest_background_color", @id)] ||= [65535, 65535, 65535]
  end


  # 設定画面の生成
  def setting(plugin, prefix)
    id = @id

    plugin.settings prefix + "検索ワード" + id.to_s do
      input("検索ワード", sym("interest_keyword", id))
      boolean("新しいツイートを優先する", sym("interest_reverse", id))
      boolean("ユーザ名も検索対象", sym("interest_user_name", id)) 
      adjustment("過去n件のツイートも取得", sym("interest_past", id), 1, 100)
      boolean("日本語のツイートのみ", sym("interest_japanese", id))
      input("プレフィックス", sym("interest_prefix", id))

      settings "カスタムスタイル" do
        boolean("カスタムスタイルを使う", sym("interest_custom_style", id))
        fontcolor("フォント", sym("interest_font_face", id), sym("interest_font_color", id))
        color("背景色", sym("interest_background_color", id))
      end
    end
  end


  # 日時文字列をパースする
  def parse_time(str)
    begin
      if str.class == Time then
        str
      else
        Time.parse(str)
      end
    rescue
      nil
    end
  end


  # 検索結果を取り出す
  def fetch()
    msg = nil

    @queue_lock.synchronize {
      if @user_config[sym("interest_reverse", @id)] then
        msg = @result_queue.pop
      else
        msg = @result_queue.shift
      end
    }

    if msg != nil then
      @last_fetch_time = Time.now
    end 

    # puts @keywords.to_s + @result_queue.size.to_s

    return msg
  end


  # メッセージ保有してる？
  def empty?()
   @result_queue.empty?
  end


  # 検索する
  def search()
    keyword = @user_config[sym("interest_keyword", @id)]

    # 検索オプションが変わったら、キャッシュを破棄する
    is_reload = [sym("interest_keyword", @id), sym("interest_user_name", @id)]
      .inject(false) { |result, key|
      result = result || (@user_config[key] != @last_config[key])

      @last_config[key] = @user_config[key]

      result
    }

    if is_reload then
      p "ID:" + @id.to_s + " setting changed"

      @queue_lock.synchronize {
        @result_queue.clear
        @last_result_time = nil
      }
    end

    query_keyword = keyword.strip.rstrip.sub(/ +/,"+")
  
    if query_keyword.empty? then
      return
    end
  
    params = {}

    query_tmp = query_keyword + "+-rt+-via"

    if @last_result_time != nil then
      query_tmp = query_tmp + "+since:" + @last_result_time.strftime("%Y-%m-%d")
    end
  
    params[:q] = query_tmp

    params[:rpp] = @user_config[sym("interest_past", @id)].to_s

    if query_keyword.empty? then
      return
    end
  
    if @user_config[:interest_japanese] then
      params[:lang] = "ja"
    end

    @service.search(params).next{ |res| 
      begin
        res = res.select { |es|
          result_tmp = false

          if es[:created_at].class == String then
            tim = parse_time(es[:created_at]) 
          else
            p "mulformed created_at:"
            p es.class
            p es

            tim = nil
          end

          if es[:message] =~ /^RT / then
            result_tmp = false
          elsif @last_result_time == nil then
            result_tmp = true
          elsif tim != nil && @last_result_time < tim then
            result_tmp = true
          else
            result_tmp = false
          end

          # ユーザ名を除外して検索する
          if !@user_config[sym("interest_user_name", @id)] then
            if result_tmp then
              if es[:message].class == String then
                msg_tmp = es[:message].gsub(/\@[a-zA-Z0-9_]+/, "");
              else
                p "mulformed message:"
                p es.class
                p es

                msg_tmp = es[:message]
              end

              if keyword.split(/ +/).inject(true) {|result, key| result && msg_tmp.upcase.include?(key.upcase)} then
                true
              else
                false
              end 
            else
              false
            end
          else
            result_tmp
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
          # puts @keywords.to_s + res.size.to_s
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
  
  # グローバル変数の初期化
  $chitandas = []



  # カスタムスタイルを選択する
  def choice_style(message, key, default)
    if message[:kininarimasu] != nil && message[:kininarimasu][:interest_custom_style] then
      message[:kininarimasu][key]
    else
      default
    end
  end


  # 検索用ループ
  def search_loop(service)
      search_keyword(service) 

    Reserver.new(UserConfig[:interest_period]){
      search_loop(service)
    } 
  end
  

  # 混ぜ込みループ
  def insert_loop(service)
      begin

        # 混ぜ込むべきインスタンスを取得
        target_chitanda = $chitandas.select { |a| a != nil }
                                    .sort { |a, b| a.last_fetch_time <=> b.last_fetch_time }
                                    .find { |chitanda| !chitanda.empty? }

        if target_chitanda != nil then
          msg = target_chitanda.fetch

          msg[:modified] = Time.now
          msg[:kininarimasu] = target_chitanda
  
          if target_chitanda[:interest_prefix].empty? then
            msg[:message] = target_chitanda[:interest_prefix] + " " + msg[:message]
          end
  
          # msg.user[:created]がたまにnilになって、nilだとプロフィールが落ちるので
          msg.user[:created] ||= Time.now

          # タイムラインに登録
          if defined?(timeline)
            timeline(:home_timeline) << [msg]
          else
            Plugin.call(:update, service, [msg])
          end

          # puts "last message :" + $result_queue.size.to_s
        end

        Reserver.new(UserConfig[:interest_insert_period]){
          insert_loop(service)
        } 
        
      rescue => e
        puts e
        puts e.backtrace
      end
  end


  # 検索
  def search_keyword(service)
    begin
      $chitandas.each { |chitanda|
        chitanda.search()
      }
    rescue => e
      puts e
      puts e.backtrace
    end
  end


  # 起動時処理
  on_boot do |service|
    (0..5 - 1).each {|i|
      $chitandas << Chitanda.new(service, UserConfig, i + 1)
    }

    # コンフィグの初期化
    UserConfig[:interest_period] ||= 60
    UserConfig[:interest_insert_period] ||= 3

    $chitandas.each {|chitanda|
      chitanda.init_user_config
    }

    # 設定画面
    settings "わたし、気になります" do
      adjustment("ポーリング間隔（秒）", :interest_period, 1, 6000)
      adjustment("混ぜ込み間隔（秒）", :interest_insert_period, 1, 600)
    end 

    $chitandas.each {|chitanda|
       if chitanda.equal?($chitandas[-1]) then
        chitanda.setting(self, "┗")
      else
        chitanda.setting(self, "┣")
      end
    }

    search_loop(service)
    insert_loop(service)
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
