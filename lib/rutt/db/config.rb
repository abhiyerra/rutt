module Rutt
  module DB
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
        $db.get_first_value("select value from config where key = ?", key)
      end

      def set(key, value)
        $db.execute("insert or replace into config(key, value) values (?, ?)", key, value)
      end
    end
  end
end
