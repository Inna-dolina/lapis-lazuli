################################################################################
# Copyright 2014 spriteCloud B.V. All rights reserved.
# Generated by LapisLazuli, version 0.0.1
# Author: "Onno Steenbergen" <onno@steenbe.nl>

require 'lapis_lazuli'
require 'lapis_lazuli/xpath'
require 'test/unit/assertions'

include LapisLazuli::XPath
include Test::Unit::Assertions

ll = LapisLazuli::LapisLazuli.instance

Given(/^I navigate to the (.*) test page$/) do |page|
  config = "server.url"
  if ll.has_env?(config)
    url = ll.env(config)
    ll.browser.goto "#{url}#{page.downcase.gsub(" ","_")}.html"
  else
    ll.error(:env => config)
  end
end

Given(/I click (the|a) (first|last|random|[0-9]+[a-z]+) (.*)$/) do |arg1, index, type|
  # Convert the type text to a symbol
  type = type.downcase.gsub(" ","_")

  pick = 0
  if ["first","last","random"].include?(index)
    pick = index.to_sym
  else
    pick = index.to_i - 1
  end
  # Options for find
  options = {}
  # Select the correct element
  options[type.to_sym] = {}
  # Pick the correct one
  options[:pick] = pick
  # Execute the find
  type_element = ll.browser.find(options)
  type_element.click
end


Given(/^I create a firefox browser named "(.*?)"( with proxy to "(.*?)")$/) do |name, proxy, proxy_url|
  browser = nil
  if proxy
    ll.log.debug("Starting with profile")
    profile = Selenium::WebDriver::Firefox::Profile.new
    profile.proxy = Selenium::WebDriver::Proxy.new :http => proxy_url
    browser = ll.browser.create :firefox, :profile => profile
  else
    browser = ll.browser.create :firefox
  end
  ll.scenario.storage.set(name, browser)
end

Given(/^I close the browser named "(.*?)"$/) do |name|
  if ll.scenario.storage.has? name
    browser = ll.scenario.storage.get name
    browser.close
  else
    ll.error("No item in the storage named #{name}")
  end
end

When(/^I find "(.*?)" and name it "(.*?)"$/) do |id, name|
  element = ll.browser.find(id)
  ll.scenario.storage.set(name, element)
end

xpath_fragment = nil
Given(/^I specify a needle "(.+?)" and a node "(.+?)" (and an empty separator )?to contains$/) do |needle, node, empty_sep|
  if empty_sep.nil?
    xpath_fragment = xp_contains(node, needle)
  else
    xpath_fragment = xp_contains(node, needle, '')
  end
end

Then(/^I expect an xpath fragment "(.*?)"$/) do |fragment|
  assert fragment == xpath_fragment, "Fragment was not as expected: got '#{xpath_fragment}' vs expected '#{fragment}'."
end

Then(/^I expect the fragment "(.*?)" to find (\d+) element\(s\)\.$/) do |fragment, n|
  elems = ll.browser.elements(:xpath => "//div[#{fragment}]")
  assert n.to_i == elems.length, "Mismatched amount: got #{elems.length} vs. expected #{n}"
end

elems = []
Given(/^I search for elements where node "(.+?)" contains "(.+?)" and not "(.+?)"$/) do |node, first, second|
  clause = xp_and(xp_contains(node, first), xp_not(xp_contains(node, second)))
  elems = ll.browser.elements(:xpath => "//div[#{clause}]")
end

Then(/^I expect to find (\d+) elements\.$/) do |n|
  assert n.to_i == elems.length, "Mismatched amount: got #{elems.length} vs. expected #{n}"
end

