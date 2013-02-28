#!/usr/bin/perl -w
$VERSION = "201302a";

# Provides a method to push PushBullet links, as well as autopushing links in
# messages. WARNING: Currently this lets Irssi save the users password. This is
# *terrible*. Based off http://scripts.irssi.org/scripts/shorturl.pl a bit.
#
# Use:
#  Set pb_key and pb_password to your user apikey and password. The api key can
# be found on your account settings page. Set pb_device to the device id you
# wish to push to. This can be found either on the main pushbullet page after
# logging in, or by using the /pb_devices command. The /pb command can then be
# use to push urls, or channel scanning can be toggled on to annoy you
# constantly. Yay!
#
# Settings:
#  /set pb_key apikey
#  /set pb_password password
#  /set pb_device device_id
#  /set pb_scan on|off          # Automatically detect and push urls
#  /set pb_scan_channels <"#channel1, ...">  # Channels to scan for urls, empty
#                                            # to scan all
#
# Commands:
#  /pb(_url) url title  # Push a link, urls cannot have spaces.
#  /pb_devices          # Get a list of device model names and ids.

use strict;
use vars qw($VERSION %IRSSI);

%IRSSI = (
    authors =>  "Derrick Staples",
    contact =>  'broiledmeat@gmail.com',
    name =>  "pbee.pl",
    description =>  "PushBullet interface.",
    license =>  "GPLv2",
    changed =>  "$VERSION"
);

use Data::Dumper;
use Irssi;
use Irssi::Irc;
use HTTP::Response;
use WWW::Curl::Easy;
use JSON;
use URI::Escape;

my $min_url_length = 5;

my $curl = WWW::Curl::Easy->new;
my ($pb_key, $pb_password, $pb_device, $scan, $scan_channels);

sub initialize {
    Irssi::settings_add_str("pbee", "pb_key", "");
    $pb_key = Irssi::settings_get_str("pb_key");

    Irssi::settings_add_str("pbee", "pb_password", "");
    $pb_password = Irssi::settings_get_str("pb_password");

    Irssi::settings_add_str("pbee", "pb_device", "");
    $pb_device = Irssi::settings_get_str("pb_device");

    Irssi::settings_add_bool("pbee", "pb_scan", 0);
    $scan = Irssi::settings_get_bool("pb_scan");

    Irssi::settings_add_str("pbee", "pb_scan_channels", "");
    $scan_channels = Irssi::settings_get_str("pb_scan_channels");

    if ($scan) {
        Irssi::signal_add_last("message public", "scan");
        Irssi::signal_add_last("ctcp action", "scan");
    } else {
        Irssi::signal_remove("message public", "scan");
        Irssi::signal_remove("ctcp action", "scan");
    }
}

sub devices {
    $curl->setopt(CURLOPT_HEADER, 1);
    $curl->setopt(CURLOPT_URL, "https:\/\/www.pushbullet.com\/api\/devices");
    $curl->setopt(CURLOPT_USERPWD, "$pb_key:$pb_password");

    my $response;
    $curl->setopt(CURLOPT_WRITEDATA, \$response);

    my $retcode = $curl->perform;

    if ($retcode == 0)
    {
        $response = HTTP::Response->parse($response)->decoded_content;
        my $json = JSON->new->allow_nonref;
        my $devices = $json->decode($response)->{"devices"};

        print("PushBullet Devices:");
        foreach my $device (@$devices)
        {
            my $id = $device->{"id"};
            my $model = $device->{"extras"}->{"model"};
            print("$model: $id");
        }
    } else {
        print("Issue retrieving devices");
    }
}

sub _push {
    my $params = shift;
    my %options = %$params;;
    my $options_str = "device_id=$pb_device";

    foreach my $key (keys %options) {
        my $val = $options{$key};
        $options_str .= "\&$key=$val";
    }

    $curl->setopt(CURLOPT_HEADER, 1);
    $curl->setopt(CURLOPT_URL, "https:\/\/www.pushbullet.com\/api\/pushes");
    $curl->setopt(CURLOPT_USERPWD, "$pb_key:$pb_password");
    $curl->setopt(CURLOPT_POST, 1);
    $curl->setopt(CURLOPT_POSTFIELDS, $options_str);
    $curl->setopt(CURLOPT_POSTFIELDSIZE, length($options_str));

    my $response;
    $curl->setopt(CURLOPT_WRITEDATA, \$response);
    my $retcode = $curl->perform;

    if ($retcode != 0)
    {
        print("Issue pushing bullet");
    }
}

sub push_url {
    my @tokens = split(/ /, @_[0]);
    my $url = shift(@tokens);
    my $title;

    if (scalar(@tokens) == 0) {
        $title = "PBee Url";
    } else {
        $title = join(' ', @tokens);
    }

    $url = encode_url($url);

    my %options = ("type" => "link", "title" => $title, "url" => $url);
    _push(\%options);
}

sub scan {
    my ($server, $data, $nick, $addr, $target) = @_;
    if (!$server || !$server->{connected}) {
      return;
    }
    return unless(is_scan_channel($target));
    $data =~ s/^\s+//;
    $data =~ s/\s+$//;
    my @urls = ();
    my ($url, $a, $return, $char, $ch, $result, $choice) = "";;
    my $same = 0;
    my $sitewas = "t";
    my @chars = ();
    return unless (($data =~ /\bhttp\:/) || ($data =~ /\bhttps\:/));
    foreach(split(/\s/, $data)) {
        if (($_ =~ /^http\:/) || ($_ =~ /^https\:/)){
            foreach $a (@urls) {
                if ($_ eq $a) {
                    $same = 1;
                    next;
                }
            }

            if ($same == 0) {
                $same = 0;
                push(@urls, $_);
            }
        }
    }

    foreach (@urls) {
        return unless (char_count($_) > $min_url_length);
        push_url($_);
    }
    return;
}

sub encode_url {
    my @chars = split(//, shift);
    my $result = "";
    foreach my $char (@chars) {
        if ($char !~ /[A-Za-z0-9]/) {
            $result .= sprintf("%%%02x", ord($char));
        } else {
            $result .= $char;
        }
    }
    return $result;
}

sub char_count {
    my @array = split(//, shift);
    return($#array + 1);
}

sub is_scan_channel {
    my $chan = shift;
    return(1) if (! $scan_channels);
    foreach(split(/\,/, $scan_channels)) {
        return(1) if ($_ =~ /$chan/i);
    }
    return 0;
}

initialize();
Irssi::signal_add("setup changed", "initialize");

Irssi::command_bind('pb', 'push_url');
Irssi::command_bind('pb_url', 'push_url');
Irssi::command_bind('pb_devices', 'devices');
