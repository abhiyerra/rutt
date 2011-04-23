module Instapaper
  class API
    Url = "http://www.instapaper.com"

    def initialize(consumer_key, consumer_secret)
      @consumer_key    = consumer_key
      @consumer_secret = consumer_secret
    end

    def authorize(username, password)
      @consumer = OAuth::Consumer.new(@consumer_key, @consumer_secret, {
          :site              => "https://www.instapaper.com",
          :access_token_path => "/api/1/oauth/access_token",
          :http_method => :post
        })

      access_token = @consumer.get_access_token(nil, {}, {
          :x_auth_username => username,
          :x_auth_password => password,
          :x_auth_mode     => "client_auth",
        })

      @access_token = OAuth::AccessToken.new(@consumer, access_token.token, access_token.secret)
    end

    def request(path, params={})
      @access_token.request(:post, "#{Url}#{path}", params)
    end
  end
end
