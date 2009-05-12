#!/usr/bin/ruby

require 'rubygems'
require 'logger'
require 'yaml'
require 'rss'
require 'open-uri'
gem 'feed-normalizer'
require 'feed-normalizer'
gem 'twitter4r'
require 'twitter'

# Make sure your ruby installation has the RSS version 0.2.4
# Read how to check it in:
# http://ruby.geraldbauer.ca/rss-atom-read-web-feeds.html
# http://www.igvita.com/2007/03/22/agile-rss-aggregator-in-ruby/

class Twitterss
  
  TWITTER_LIMIT = 140
  
  @@past_posts_file = File.join(ENV['HOME'], '.twitterss_history')
  
  def initialize(config_file, logger)
    @config = YAML.load(File.read(config_file))
    @logger = logger
    
    File.open(@@past_posts_file, "w").close if !File.exists?(@@past_posts_file)
    @past_posts = YAML.load(File.read(@@past_posts_file))
    @past_posts ||= {}
  end

  def run
    @config.each do |name, config|
      @logger.debug "#{name}:"
      @logger.debug "parsing #{config['rss']} " 
      max = config['max'] || 5
      feed = delete_already_posted(name,FeedNormalizer::FeedNormalizer.parse(open(config['rss'])) , max)
      feed.items[0,max].each do |item|
        generate_message(item)
        
        if posted?(name, item)
          @logger.debug "\"#{clean_title(item.title.to_s)}\"...skipped"
        else
          twitter_client = Twitter::Client.new(:login => config['login'], :password => config['password'])
          twitter_client.status(:post, generate_message(item))
          
          mark_posted(name, item)
          @logger.debug "\"#{clean_title(item.title.to_s)}\"...posted"
        end
      end
      
    end
  end  
  
  def self.dump_usage
    puts "Usage:"
    puts "  twitterss [-v] <configuration file>"
  end
  
private
  
def delete_already_posted (name, feed, max)
  count = 0;
  while (max > count) && (feed.items.size>0)
    if posted?(name, feed.items[count])
      feed.items.delete_at(count)
    else
      if (feed.items.size <= 0)
        count = max+1;
      else
        count = count +1
      end
    end  
  end
  feed
end

  def posted?(name, item)
    @past_posts[name] ||= {}
    @past_posts[name][clean_link(item.urls[0].to_s)]
  end
  
  def mark_posted(name, item)
    @past_posts[name] ||= {}
    @past_posts[name][clean_link(item.urls[0].to_s)] = true
    dump_state!
  end
  
  def dump_state!
    @logger.debug "dumping state..."
    File.open(@@past_posts_file, "w") do |f|
      YAML.dump(@past_posts, f)
    end
  end
  
  # this two functions are a hack
  # TODO:Fix this. Make the parsing of the links and titles mor ruby-ish
  #      this looks like ANSI C !
  def clean_link (link)        
    if (link.include?('href='))
      link = link.match(/href=["]?([^'"]*)[" ]/mi) 
      link = link.to_s.strip
      link = link[6,link.length - 7]
    end
    link        
  end
  
  def clean_title (title)
    if (title.include?('<title type'))
      title = title.match(/[>]([^"]*)[<]/)
      title = title.to_s.strip
      title = title[1,title.length-2]
    end
    title 
  end
  
  def generate_message(item)
    link = clean_link(item.urls[0].to_s)
    short_link = open('http://bit.ly/api?url=' + link, "UserAgent" => "Ruby-ShortLinkCreator").read
    limit = TWITTER_LIMIT - short_link.length
    message = "#{clean_title(item.title.to_s).strip} (Via GoogleReader)"[0,limit-2] # 2 for '..'
    message << "..#{short_link}"
    message
  end
end

config_file = ARGV[-1]
logger = Logger.new(STDOUT)
logger.level = ARGV.include?("-v") ? Logger::DEBUG : Logger::WARN

if config_file.nil? || config_file.empty?
  Twitterss.dump_usage
else
  twitterss = Twitterss.new(config_file, logger)
  twitterss.run
end