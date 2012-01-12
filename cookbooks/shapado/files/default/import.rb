#!/usr/bin/env ruby

if !ARGV[0]
  puts "Usage: #{$0} <dirname>"
  exit 1
end

require File.expand_path('../../config/environment', __FILE__)

group_info = JSON.parse(File.read(ARGV[0]+"/groups.json"))

Dir.glob(ARGV[0]+"/*.json").each do |filepath|
  coll_name = File.basename(filepath, ".json")

  cmd = "mongoimport -d '#{MongoMapper.database.name}' -c '#{coll_name}' --file '#{filepath}'"
  system(cmd)
end

group = Group.where(:subdomain => group_info["subdomain"]).first
group.domain = AppConfig.domain
group.save!

puts "Updating objects..."
%w[groups users badges answers questions].each do |cname|
  coll = MongoMapper.database.collection(cname)
  coll.find.each do |q|
    %w[activity_at last_target_date created_at updated_at].each do |key|
      if q[key].is_a?(String)
        q[key] = Time.parse(q[key])
      end
    end

    if q["comments"]
      q["comments"].each do |comment|
        %w[created_at updated_at].each do |key|
          if comment[key].is_a?(String)
            comment[key] = Time.parse(comment[key])
          end
        end
      end
    end
    coll.save(q)
  end
end

group.questions.map{|q| q.save }