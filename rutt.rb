require 'rubygems'
require 'ncurses'
require 'logger'
require 'optparse'
require 'ncurses'
require 'rss/1.0'
require 'rss/2.0'
require 'open-uri'
require 'dm-core'
require 'dm-migrations'


class Feed
  include DataMapper::Resource

  property :id, Serial
  property :title, String
  property :url, String
  property :created_at, DateTime
  property :updated_at, DateTime

  has n, :items

  after :save, :refresh

  before :destroy do
    self.items.each do |item|
      item.destroy
    end
  end

  def refresh
    content = open(sel.url).read
    rss = RSS::Parser.parse(content, false)

    self.title = rss.channel.title
    rss.channel.items.each do |item|
      Item.create({
          :title        => item.title,
          :url          => item.link,
          :published_at => item.date,
        })
    end
  end

  def unread
    self.items.count(:is_read => false)
  end
end


class Item
  include DataMapper::Resource

  property :id, Serial

  property :title, String
  property :url, String
  property :description, Text
  property :is_read, Boolean
  property :like_this, Boolean
  property :published_at, DateTime


  def mark_as_read
    self.is_read = true
    self.save
  end

  def mark_as_unread
    self.is_read = false
    self.save
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
    @_feeds = Feed.all
  end

  def display_feeds
    @cur_y = @min_y

    @_feeds[@limit[0]..@limit[1]].each do |feed|
      next if feed.unread == 0

      @stdscr.move(@cur_y, 0)
      @stdscr.addstr("  #{feed.unread}/#{feed.items.count}\t\t#{feed.title}\n")
      @feeds[@cur_y] = feed

      @cur_y += 1
    end

    @cur_y = @min_y
    @stdscr.refresh
  end

  def window(start_limit=nil, end_limit=nil)
    @stdscr.clear

    @limit = [start_limit, end_limit] if start_limit || end_limit

    display_menu
    display_feeds
    move_pointer(0)
  end

  def event_loop
    window(0, @stdscr.getmaxy - 2)

    loop do
      c = @stdscr.getch

      if c > 0 && c < 255
        case c.chr
        when /q/i
          break
        when /a/i
          # no-op
        when /r/i
          cur_y = @cur_y

          Feed.all.each { |feed| feed.refresh }

          reload_feeds
          window
          move_pointer(cur_y, move_to=True)
        when /d/i
          cur_y = @cur_y

          stdscr.clear()
          display_menu()
          feed = @feeds[cur_y]
          @stdscr.move(2, 0)
          @stdscr.addstr("Are you sure you want to delete #{feed.title}? ")
          d = @stdscr.getch()
          if chr(c) =~ /y/i
            feed.remove
            reload_feeds
            window
            move_pointer(cur_y, move_to=True)
          end
        when /p/i
          window(@limit[0] - curses.LINES - 2, @limit[0])
        when /n/i
          window(@limit[1], @limit[1] + curses.LINES - 2)
        when / /
          cur_y = @cur_y
          item_screen = ItemScreen.new(@stdscr, @feeds[cur_y])
          item_screen.event_loop

          window
          move_pointer(cur_y, move_to=true)
        end
      else
        case c
        when curses.KEY_UP
          move_pointer(-1)
        when curses.KEY_DOWN
          move_pointer(1)
        end
      end
    end
  end
end

class ItemScreen < Screen
  # def initialize(stdscr, feed)
  #   @feed = feed
  #   @items = {}
  #   @menu = " i:quit r:refresh m:mark as read u:mark as unread a:mark all as read b:open in browser"

  #   super(stdscr)
  # end

  # def display_items
  #   @cur_y = @min_y

  #   for item in @feed.items[@limit[0]..@limit[1]]:
  #       @stdscr.addstr("  #{!item.is_read ? 'N' : ' '}\t#{item.published_at}\t#{item.title}\n")

  #     @items[@cur_y] = item
  #     @cur_y += 1
  #   end

  #   @cur_y = @min_y
  #   @stdscr.refresh
  # end

  # def window(start_limit=nil, end_limit=nil)
  #   @stdscr.clear

  #   if start_limit or end_limit:
  #       @limit = [start_limit, end_limit]
  #   end

  #   display_menu
  #   display_items
  #   move_pointer(0)
  # end

  # def event_loop
  #   window(0, curses.LINES - 2)

  #   loop do
  #     c = @stdscr.getch()

  #     case chr(c)
  #     when /[iq]/i
  #       break
  #     when /a/i
  #       @feed.items.each { |item| item.mark_as_read }

  #       window
  #       move_pointer(@cur_y, move_to=true)
  #     when /p/i
  #       window(@limit[1] - curses.LINES - 2, @limit[1])
  #     when /n/i
  #       window(@limit[1], @limit[1] + curses.LINES - 2)
  #     when /b/i
  #       cur_y = @cur_y
  #       @items[cur_y].mark_as_read
  #       webbrowser.open_new_tab(@items[cur_y].url)
  #     when /m/i
  #       cur_y = @cur_y
  #       @items[cur_y].mark_as_read
  #       window()
  #       move_pointer(cur_y + 1, move_to=True)
  #     when /u/i
  #       cur_y = @cur_y
  #       @items[cur_y].mark_as_unread()
  #       window()
  #       move_pointer(cur_y, move_to=True)
  #     when /r/i
  #       feed.refresh
  #       window
  #     when / /
  #       cur_y = @cur_y

  #       content_screen = ContentScreen(@stdscr, @items[@cur_y])
  #       content_screen.event_loop

  #       window
  #       move_pointer(cur_y, move_to=True)
  #     end

  #     case c
  #     when curses.KEY_UP
  #       move_pointer(-1)
  #     when curses.KEY_DOWN
  #       move_pointer(1)
  #     end
  #   end
  # end
end





# class ContentScreen(Screen):
#     def initialize(stdscr, item):
#         self.item = item
#       self.menu = "i:back b:open in browser"
#     end


#     def get_content():
#         render_cmd = "elinks -dump -dump-charset ascii -force-html %s" % self.item.url
#         self.content = os.popen(render_cmd).read().encode("utf-8").split("\n")

#     def move_pointer(pos):
#         if self.cur_line + pos < 0:
#             return

#         self.stdscr.addstr(1, 2, "%s (%s)\n" % (self.item.title, self.item.url), curses.A_BOLD)

#         self.cur_line = self.cur_line + pos

#         lines = self.content[self.cur_line:self.cur_line + curses.LINES - 5]
#         cur_y = 2
#         for line in lines:
#             self.stdscr.addstr(cur_y, 2, "%s\n" % line)
#             cur_y += 1

#         self.stdscr.refresh()

#     def window(pointer_pos):
#         self.stdscr.clear()
#         self.display_menu()
#         self.move_pointer(pointer_pos)

#     def event_loop():
#         self.cur_line = 0
#         self.get_content()
#         self.window(0)

#         while True:
#             c = self.stdscr.getch()
#             if 0 < c < 256:
#                 if chr(c) in 'IiQq':
#                     self.item.mark_as_read()
#                     break
#                 elif chr(c) in 'Bb':
#                     webbrowser.open_new_tab(self.item.url)
#                 elif chr(c) in ' ':
#                     self.window(10)
#             else:
#                 if c == curses.KEY_UP:
#                     self.window(-1)
#                 elif c == curses.KEY_DOWN:
#                     self.window(1)




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
  feed_screen.event_loop
ensure
  Ncurses.endwin()
end


def main
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: rutt.rb [options]"

    opts.on('-a', '--add FEED', "Add a feed") do |feed|
      feed = Feed.new(url)
      exit
    end

    opts.on('-r', '--reload', "Reload all feeds.") do
      Feed.all.each { |f| f.reload }
      exit
    end

#    opts.on('-l', '--list-feeds', action='store_true', help="List the feeds")

  end.parse!

  DataMapper.setup(:default, 'sqlite://rutt2.db')
  DataMapper.auto_migrate!

  start_screen
end

main
