module Rutt
  module Screen
    class Content < Base
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
