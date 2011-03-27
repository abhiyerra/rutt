require 'rubygems'

require 'launchy'
require 'ncurses'
require 'nokogiri'
require 'open-uri'
require 'optparse'
require 'rss/1.0'
require 'rss/2.0'
require 'sqlite3'
require 'feedparser'
require 'parallel'

$db = SQLite3::Database.new('rutt.db')
$db.results_as_hash = true

module Config
  extend self

  def make_table!
    $db.execute(%{
         create table if not exists config (
                      id integer PRIMARY KEY,
                      key text,
                      value text,
                      UNIQUE(key))
      })
  end

  def get(key)
    $db.execute("select key, value from config where key = ?", key)
  end

  def set(key, value)
    $db.execute("insert or update config(key, value) values (?, ?)", key, value)
  end
end

module Opml
  def self.get_urls(file)
    doc = Nokogiri::XML(open(file))

    urls = []

    doc.xpath('opml/body/outline').each do |outline|
      if outline['xmlUrl']
        urls << outline['xmlUrl']
      else
        (outline/'outline').each do |outline2|
          urls << outline2['xmlUrl']
        end
      end
    end

    return urls
  end
end

module Feed
  extend self

  def make_table!
    $db.execute(%{
         create table if not exists feeds (
                      id integer PRIMARY KEY,
                      title text,
                      url text,
                      update_interval integer default 3600,
                      created_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                      updated_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                      UNIQUE(url))
      })
  end

  def add(url, refresh=true)
    $db.execute("insert or ignore into feeds (url) values ('#{url}')")
    $db.execute("select * from feeds where id = (select last_insert_rowid())") do |feed|
      refresh_for(feed)
    end if refresh
  end

  def get(id)

  end

  def delete(feed)
    $db.execute("delete from items where feed_id = ?", feed['id'])
    $db.execute("delete from feeds where id = ?", feed['id'])
  end

  def all(min_limit=0, max_limit=-1)
    $db.execute(%{
       select f.*,
              (select count(*) from items iu where iu.feed_id = f.id) as num_items,
              (select count(*) from items ir where ir.read = 0 and ir.feed_id = f.id) as unread
       from feeds f where unread > 0 order by id desc limit #{min_limit},#{max_limit}
    })
  end

  def refresh
    feeds = $db.execute("select * from feeds")
    results = Parallel.map(feeds, :in_threads => 8) do |feed|
      refresh_for(feed)
    end
  end

  def refresh_for(feed)
    content = open(feed['url']).read
    rss = FeedParser::Feed::new(content)

    puts rss.title

    $db.execute("update feeds set title = ? where id = ?", rss.title, feed['id'])

    rss.items.each do |item|
      $db.execute("insert or ignore into items (feed_id, title, url, published_at) values (?, ?, ?, ?)", feed['id'], item.title, item.link, item.date.to_i)
    end
  rescue Exception => e
    # no-op
  end

  def unread(feed_id)
    $db.execute("select * from items where feed_id = ? and read = 0", feed)
  end

  def mark_as_read(feed)
    $db.execute("update items set read = 1 where feed_id = ?", feed['id'])
  end
end


module Item

  extend self

  def make_table!
    $db.execute(%{
      create table if not exists items (
                      id integer PRIMARY KEY,
                      feed_id integer,
                      title text,
                      url text,
                      description text,
                      read int default 0,
                      prioritize int default 0,
                      published_at DATE NOT NULL DEFAULT (datetime('now','localtime')),
                      created_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                      updated_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                      UNIQUE(url),
                      FOREIGN KEY(feed_id) REFERENCES feeds(id))
    })
  end

  def all(feed, min_limit=0, max_limit=-1)
    $db.execute("select * from items where feed_id = ? limit #{min_limit},#{max_limit}", feed['id'])
  end

  def mark_as_unread(item)
    $db.execute("update items set read = 0 where id = #{item['id']}")
  end

  def mark_as_read(item)
    $db.execute("update items set read = 1 where id = #{item['id']}")
  end
end

class Screen
  def initialize(stdscr)
    @stdscr = stdscr

    @min_y = 1
    @max_y = @stdscr.getmaxy

    @min_limit = @min_y - 1
    @max_limit = @max_y - 5

    @cur_y = 1
    @cur_x = 0
  end

  def incr_page
    @min_limit =  @max_limit
    @max_limit += (@max_y - 5)
  end

  def decr_page
    @max_limit =  @min_limit
    @min_limit -= (@max_y - 5)

    if @max_limit <= 0
      @min_limit = @min_y - 1
      @max_limit = @max_y - 5
    end
  end

  def display_menu
    @stdscr.clear
    @stdscr.move(0, 0)
    @stdscr.addstr(" rutt #{@menu}\n")
  end

  def move_pointer(pos, move_to=false)
    @stdscr.move(@cur_y, 0)
    @stdscr.addstr(" ")

    if move_to == true
      @cur_y = pos
    else
      @cur_y += pos
    end

    @stdscr.move(@cur_y, 0)
    @stdscr.addstr(">")
  end
end


class FeedScreen < Screen
  def initialize(stdscr)
    @menu = "q:Quit d:delete r:refresh all"

    super(stdscr)
  end

  def display_feeds
    @cur_y = @min_y

    @feeds = Feed::all(@min_limit, @max_limit)
    @feeds.each do |feed|
 #     next if feed['unread'] == 0  # This should be configurable: feed.showread

      @stdscr.move(@cur_y, 0)
      @stdscr.addstr("  #{feed['unread']}/#{feed['num_items']}\t\t#{feed['title']}\n")

      @cur_y += 1
    end

    @cur_y = @min_y
    @stdscr.refresh
  end

  def window
    @stdscr.clear

    display_menu
    display_feeds
    move_pointer(0)
  end

  def loop
    window

    while true do
      c = @stdscr.getch

      if c > 0 && c < 255
        case c.chr
        when /q/i
          break
        when /a/i
          # no-op
        when /r/i
          cur_y = @cur_y

          Feed::refresh

          window
          move_pointer(cur_y, move_to=true)
        when /d/i
          cur_y = @cur_y

          @stdscr.clear
          display_menu
          feed = @feeds[cur_y]
          @stdscr.move(2, 0)
          @stdscr.addstr("Are you sure you want to delete #{feed['title']}? ")
          d = @stdscr.getch
          if d.chr =~ /y/i
            Feed::delete(feed)
            window
            move_pointer(cur_y, move_to=true)
          end
        when /p/i
          decr_page
          window
        when /n/i
          incr_page
          window
        when / /
          cur_y = @cur_y
          @stdscr.addstr("#{@feeds[cur_y]}")
          item_screen = ItemScreen.new(@stdscr, @feeds[cur_y - 1])
          item_screen.loop

          window
          move_pointer(cur_y, move_to=true)
        end
      else
        case c
        when Ncurses::KEY_UP
          move_pointer(-1)
        when Ncurses::KEY_DOWN
          move_pointer(1)
        end
      end
    end
  end
end

class ItemScreen < Screen
  def initialize(stdscr, feed)
    @feed = feed
    @menu = " i:quit r:refresh m:mark as read u:mark as unread a:mark all as read b:open in browser"

    super(stdscr)
  end

  def display_items
    @cur_y = @min_y

    @items = Item::all(@feed, @min_limit, @max_limit)
    @items.each do |item|
      @stdscr.addstr("  #{item['read'].to_i == 0 ? 'N' : ' '}\t#{item['published_at']}\t#{item['title']}\n")
      @cur_y += 1
    end

    @cur_y = @min_y
    @stdscr.refresh
  end

  def window
    @stdscr.clear

    display_menu
    display_items
    move_pointer(0)
  end

  def loop
    window

    while true do
      c = @stdscr.getch

      if c > 0 && c < 255
        case c.chr
        when /[iq]/i
          break
        when /a/i
          Feed::mark_as_read(@feed)
          window
          move_pointer(@cur_y, move_to=true)
        when /p/i
          decr_page
          window
        when /n/i
          incr_page
          window
        when /b/i
          cur_y = @cur_y - 1
          Item::mark_as_read(@items[cur_y])
          Launchy.open(@items[cur_y]['url'])
          window
          move_pointer(cur_y, move_to=true)
        when /m/i
          cur_y = @cur_y - 1
          Item::mark_as_read(@items[cur_y])
          window
          move_pointer(cur_y + 1, move_to=true)
        when /u/i
          cur_y = @cur_y - 1
          Item::mark_as_unread(@items[cur_y])
          window
          move_pointer(cur_y + 1, move_to=true)
        when /r/i
          Feed::refresh_for(@feed)
          window
        when / /
          content_screen = ContentScreen.new(@stdscr, @items[@cur_y - 1])
          content_screen.loop

          window
          move_pointer(@cur_y, move_to=true)
        end
      else
        case c
        when Ncurses::KEY_UP
          move_pointer(-1)
        when Ncurses::KEY_DOWN
          move_pointer(1)
        end
      end
    end
  end
end





class ContentScreen < Screen
  def initialize(stdscr, item)
    @item = item
    @menu = "i:back b:open in browser"

    super(stdscr)
  end

  def display_content
    @content = `elinks -dump -dump-charset ascii -force-html #{@item['url']}`
    @content = @content.split("\n")

    @stdscr.addstr(" #{@item['title']} (#{@item['url']})\n\n")

    lines = @content[@min_limit..@max_limit]
    lines.each { |line| @stdscr.addstr("  #{line}\n") } if lines

    @stdscr.refresh
  end

  def window
    @stdscr.clear
    display_menu
    display_content
  end

  def loop
    @cur_line = 0

    window

    while true do
      c = @stdscr.getch
      if c > 0 && c < 255
        case c.chr
        when /[iq]/i
          Item::mark_as_read(@item)
          break
        when /b/i
          Launchy.open(@item['url'])
        end
      else
        case c
        when Ncurses::KEY_UP
          decr_page
          window
        when Ncurses::KEY_DOWN
          incr_page
          window
        end
      end
    end

  end
end



def start_screen
  stdscr = Ncurses.initscr()

  Ncurses.start_color();
  Ncurses.cbreak();
  Ncurses.noecho();
  Ncurses.keypad(stdscr, true);

  stdscr.clear

  feed_screen = FeedScreen.new(stdscr)
  feed_screen.loop
ensure
  Ncurses.endwin()
end


def main
  Config::make_table!
  Feed::make_table!
  Item::make_table!

  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: rutt.rb [options]"

    opts.on('-a', '--add FEED', "Add a feed") do |url|
      Feed::add(url)
      exit
    end

    opts.on('-r', '--refresh', "Refresh feeds.") do
      Feed::refresh
      exit
    end

    opts.on('-o', '--import-opml FILE', "Import opml") do |file|
      urls = Opml::get_urls(file)

      urls.each do |url|
        puts "Adding #{url}"
        Feed::add(url, false)
      end

      exit
    end

#    opts.on('-l', '--list-feeds', action='store_true', help="List the feeds")

  end.parse!


  start_screen
end

main
