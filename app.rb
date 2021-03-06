require "sinatra"
require "json"

get '/' do
  erb :home
end

post '/timeline' do
  @name = params[:name]
  if no_wiki_article(@name)
    erb :notfound
  else
    url_safe_name = @name.gsub(/ +/,'+')
    query = "http://localhost:8983/solr/collection1/select/?indent=on&q=#{url_safe_name}&wt=json"
    @json = get_json(@name, query)
    erb :timeline
  end
end

helpers do
  def title
    'Time Glider'
  end

  # grab the json from the SOLR link and load it into a ruby hash
  # then populate the hash with the relevant details
  # and return a JSON object corresponding to the modified hash 
  def get_json(name, link)
    # get a link to the JSON returned by Solr
    json_str = `curl "#{link}"`
    json_hash = JSON.load(json_str)

    events = json_hash["response"]["docs"] # events is an array of hashes

    @result = JSON.parse(IO.read('template.json')) # load the template_hash

    cap_name = name.split.map { |w| w.capitalize }.join

    @result["timeline"]["headline"] = "Timeline for #{name}"
    @result["timeline"]["text"] = "<p>Here's the timeline for #{cap_name}.</p>"

    #link to the wikipedia page
    @result["timeline"]["asset"] = {
      "media" => get_wiki_article(name),
      "credit" => "",
      "caption" => "<em>Click on the title above to read the full Wikipedia article for #{cap_name}</em>"
    }

    #clear the "date" key from result
    @result["timeline"]["date"] = []

    events.each do |event|
      headline = event["name"]
      date = parse_date(event["date"])

      link = "http://www.hindustantimes.com/a/a/a/" + event["link"]
      body = event["body"]
      image = event["images"][0].split(',').first || event["images"][0].chop

      # puts "+%"*45
      # puts body
      # puts "+%"*45

      sbody = body.gsub('"', '\\\"')
      sbody = body.gsub('"', '\"')
      # sbody = sbody.gsub("'", "''")
      sbody = sbody.gsub('`', "'")

      summary_array = `python summarize.py "#{sbody}"`

      unless summary_array.empty?
        summary_array = JSON.load(summary_array) 
        summary_uniq = []
        10.times { summary_uniq << summary_array.sample }
        summary_uniq.uniq!
        summary_uniq = summary_uniq[0..2]
      else
        # puts "=|"*50
        # puts summary_uniq
        # puts "=|"*50
        summary_uniq = ["filler"]
      end

      if image.empty?
        media = ""
        summary_uniq.each do |sentence|
          addition = "<blockquote>#{sentence}</blockquote>"
          media << addition unless (media+addition).length > 500
        end
        # media = "<blockquote>#{summary_array.sample}</blockquote>"
      else
        media = image
      end

      new_event = {
        "startDate" => date,
        "headline" => headline,
        "text" => "<a href=#{link}>Link to the article</a>",
        "asset" => {
          # "media" => link,
          # "media" => "<blockquote>Sample 1</blockquote><blockquote>Sample 2</blockquote>",
          "media" => media,
          "credit" => "",
          "caption" => ""
        }
      }
      @result["timeline"]["date"].push(new_event)
    end

    JSON.dump(@result)
  end

  # This extracts the TimelineJS-friendly-date from the SOLR response date
  # Sample input: "First Published: 16:30 IST(12/2/2010)"
  # Output: 2010,2,12
  def parse_date(date)
    date[/\d+\/\d+\/\d+/].split('/').reverse.join(',')
  end

  # returns true if the name searched for has no wikipedia article
  # false otherwise
  def no_wiki_article(name)
    search = name.strip.gsub(/ +/, '+') # remove leading/trailing whitespace and replace all spaces in name with +
    result_string = `curl "http://en.wikipedia.org/w/api.php?action=opensearch&search=#{search}"`
    result_json = JSON.load(result_string)[1]
    result_json.empty?
  end

  def get_wiki_article(name)
    name = name.strip.gsub('\s+','+').capitalize
    "http://en.wikipedia.org/wiki/#{name}"
  end
end