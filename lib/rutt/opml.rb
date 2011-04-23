module Rutt
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
end
