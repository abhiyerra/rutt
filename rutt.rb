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

# gem install launchy
# gem install sqlite3
# gem install ncurses
# gem install ruby-feedparser

$db = SQLite3::Database.new('rutt.db')
$db.results_as_hash = true

module Config

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

  def all
    $db.execute(%{
       select f.*,
              (select count(*) from items iu where iu.feed_id = f.id) as num_items,
              (select count(*) from items ir where ir.read = 0 and ir.feed_id = f.id) as unread
       from feeds f
    })
  end

  def refresh
    $db.execute("select * from feeds") do |feed|
      refresh_for(feed)
    end
  end

  def refresh_for(feed)
    content = open(feed['url']).read
    rss = FeedParser::Feed::new(content)

    $db.execute("update feeds set title = ? where id = ?", rss.title, feed['id'])

    rss.items.each do |item|
      $db.execute("insert or ignore into items (feed_id, title, url, published_at) values (?, ?, ?, ?)", feed['id'], item.title, item.link, item.date.to_i)
    end
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

  def all(feed=nil)
    if feed
      $db.execute("select * from items")
    else
      $db.execute("select * from items where feed_id = ?", feed)
    end
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

    @cur_y = 1
    @cur_x = 0
  end

  def display_menu
    @stdscr.clear()
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
    @feeds = {}
    @menu = "q:Quit d:delete r:refresh all"

    reload_feeds

    super(stdscr)
  end

  def reload_feeds
    @_feeds = Feed::all
  end

  def display_feeds
    @cur_y = @min_y

    @_feeds[@limit[0]..@limit[1]].each do |feed|

#      next if feed.unread == 0

      @stdscr.move(@cur_y, 0)
      @stdscr.addstr("  #{feed['unread']}/#{feed['num_items']}\t\t#{feed['title']}\n")
      @feeds[@cur_y] = feed

      @cur_y += 1
    end

    @cur_y = @min_y
    @stdscr.refresh
  end

  def window(start_limit=nil, end_limit=nil)
    @stdscr.clear

    @limit = [start_limit, end_limit] if start_limit || end_limit

    reload_feeds
    display_menu
    display_feeds
    move_pointer(0)
  end

  def loop
    window(0, @stdscr.getmaxy - 2)

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
          window(@limit[0] - @stdscr.getmaxy - 2, @limit[0])
        when /n/i
          window(@limit[1], @limit[1] + @stdscr.getmaxy - 2)
        when / /
          cur_y = @cur_y
          item_screen = ItemScreen.new(@stdscr, @feeds[cur_y])
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

  def reload_items
    @items = Item::all(@feed)
  end

  def display_items
    @cur_y = @min_y

    @items[@limit[0]..@limit[1]].each do |item|
      @stdscr.addstr("  #{item['read'].to_i == 0 ? 'N' : ' '}\t#{item['published_at']}\t#{item['title']}\n")

      @items[@cur_y] = item
      @cur_y += 1
    end

    @cur_y = @min_y
    @stdscr.refresh
  end

  def window(start_limit=nil, end_limit=nil)
    @stdscr.clear

    @limit = [start_limit, end_limit] if start_limit || end_limit

    reload_items
    display_menu
    display_items
    move_pointer(0)
  end

  def loop
    window(0, @stdscr.getmaxy - 2)

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
          window(@limit[1] - @stdscr.getmaxy - 2, @limit[1])
        when /n/i
          window(@limit[1], @limit[1] + @stdscr.getmaxy - 2)
        when /b/i
          cur_y = @cur_y
          Item::mark_as_read(@items[cur_y])
          Launchy.open(@items[cur_y]['url'])
        when /m/i
          cur_y = @cur_y
          Item::mark_as_read(@items[cur_y])
          window
          move_pointer(cur_y + 1, move_to=true)
        when /u/i
          cur_y = @cur_y
          Item::mark_as_unread(@items[cur_y])
          window
          move_pointer(cur_y + 1, move_to=true)
        when /r/i
          Feed::refresh_for(@feed)
          window
        when / /
          cur_y = @cur_y

          content_screen = ContentScreen.new(@stdscr, @items[@cur_y])
          content_screen.loop

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





class ContentScreen < Screen
  def initialize(stdscr, item)
    @item = item
    @menu = "i:back b:open in browser"

    super(stdscr)
  end

  def get_content
    @content = `elinks -dump -dump-charset ascii -force-html #{@item['url']}`
  end

  def move_pointer(pos)
    return if @cur_line + pos < 0

    @stdscr.addstr("#{@item['title']} (#{@item['url']})\n")
    @cur_line += pos

    lines = @content[@cur_line..@cur_line + @stdscr.getmaxy - 5]
    cur_y = 2

    while cur_y < @cur_line + @stdscr.getmaxy - 5 do
      @stdscr.addstr("#{lines[cur_y]}\n")
      cur_y += 1
    end

    @stdscr.refresh
  end

  def window(pointer_pos)
    @stdscr.clear()
    display_menu()
    move_pointer(pointer_pos)
  end

  def loop
    @cur_line = 0
    get_content()
    window(0)

    while true do
      c = @stdscr.getch()
      if c > 0 && c < 255
        case c.chr
        when /iq/i
          Item::mark_as_read(@item)
          return
        when /b/i
          Launchy.open(@item['url'])
        when / /i
          window(10)
        end
      else
        case c
        when Ncurses::KEY_UP
          window(-1)
        when Ncurses::KEY_DOWN
          window(1)
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

  # Initialize few color pairs
  # Ncurses.init_pair(1, COLOR_RED, COLOR_BLACK);
  # Ncurses.init_pair(2, COLOR_BLACK, COLOR_WHITE);
  # Ncurses.init_pair(3, COLOR_BLACK, COLOR_BLUE);
  # stdscr.bkgd(Ncurses.COLOR_PAIR(2));

  stdscr.clear

  feed_screen = FeedScreen.new(stdscr)
  feed_screen.loop
ensure
  Ncurses.endwin()
end


def main
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
