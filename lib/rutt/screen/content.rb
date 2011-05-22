module Rutt
  module Screen
    class Content < Base
      def initialize(stdscr, item)
        super(stdscr)

        @item = item
        @menu = "i:back b:open in browser"

        # Get the content
        source = open(@item['url']).read
        content = Nokogiri::HTML(::Readability::Document.new(source).content).text

        @content = content.split("\n").map do |s|
          s.gsub(/.{0,74}(?:\s|\Z)/){($& + 5.chr).gsub(/\n\005/,"\n")}.gsub(/((\n|^)[>|\s]*[>|].*?)\005/, "\\1").gsub(/\005/,"\n").split("\n") << "\n"
        end.flatten

        @pages = @content / @max_y
      end

      def display_content
#        @content = `elinks -dump -dump-charset ascii -force-html #{@item['url']}`

        @cur_y = @min_y
        @stdscr.move(@cur_y, 0)
        @stdscr.addstr(" #{@item['title']}\n")
        @cur_y += 1
        @stdscr.move(@cur_y, 0)
        @stdscr.addstr(" #{@item['url']}\n")
        @cur_y += 1

        @pages[@cur_page].each do |line|
          @stdscr.move(@cur_y, 0)
          @stdscr.addstr("  #{line}\n")

          @cur_y += 1
        end
        @cur_y = @min_y

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
              DB::Item::mark_as_read(@item)
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
  end
end
