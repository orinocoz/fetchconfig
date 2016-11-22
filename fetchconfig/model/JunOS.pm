# fetchconfig - Retrieving configuration for multiple devices
# Copyright (C) 2006 Everton da Silva Marques
#
# fetchconfig is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# fetchconfig is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with fetchconfig; see the file COPYING. If not, write to the
# Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301 USA.
#
# $Id: JunOS.pm,v 1.1 2012/04/04 20:29:44 evertonm Exp $

package fetchconfig::model::JunOS; # fetchconfig/model/JunOS.pm

use strict;
use warnings;
use Net::Telnet;
use fetchconfig::model::Abstract;

@fetchconfig::model::JunOS::ISA = qw(fetchconfig::model::Abstract);

####################################
# Implement model::Abstract - Begin
#

sub label {
    'junos';
}

# "sub new" fully inherited from fetchconfig::model::Abstract

sub fetch {
    my ($self, $file, $line_num, $line, $dev_id, $dev_host, $dev_opt_tab) = @_;

    my $saved_prefix = $self->{log}->prefix; # save log prefix
    $self->{log}->prefix("$saved_prefix: dev=$dev_id host=$dev_host");

    my @conf = $self->do_fetch($file, $line_num, $line, $dev_id, $dev_host, $dev_opt_tab);

    # restore log prefix
    $self->{log}->prefix($saved_prefix);

    @conf;
}

#
# Implement model::Abstract - End
##################################

sub chat_login {
    my ($self, $t, $dev_id, $dev_host, $dev_opt_tab) = @_;
    my $ok;

    my $login_prompt = '/login: $/';

    # chat_banner is used to allow temporary modification
    # of timeout throught the 'banner_timeout' option

    my ($prematch, $match) = $self->chat_banner($t, $dev_opt_tab, $login_prompt);
    if (!defined($prematch)) {
	$self->log_error("could not find login prompt: $login_prompt");
	return undef;
    }

    $self->log_debug("found login prompt: [$match]");

    if ($match =~ /^login:/) {
	my $dev_user = $self->dev_option($dev_opt_tab, "user");
	if (!defined($dev_user)) {
	    $self->log_error("login username needed but not provided");
	    return undef;
	}

	$ok = $t->print($dev_user);
	if (!$ok) {
	    $self->log_error("could not send login username");
	    return undef;
	}

	($prematch, $match) = $t->waitfor(Match => '/Password:\s*$/');
	if (!defined($prematch)) {
	    $self->log_error("could not find password prompt");
	    return undef;
	}

	$self->log_debug("found password prompt: [$match]");
    }

    if ($match =~ /^Password/) {
	my $dev_pass = $self->dev_option($dev_opt_tab, "pass");
        if (!defined($dev_pass)) {
	    $self->log_error("login password needed but not provided");
	    return undef;
        }

	$ok = $t->print($dev_pass);
	if (!$ok) {
	    $self->log_error("could not send login password");
	    return undef;
	}

        ($prematch, $match) = $t->waitfor(Match => '/(\S+)>\s$/');
	if (!defined($prematch)) {
	    $self->log_error("could not find command prompt");
	    return undef;
	}

	$self->log_debug("found command prompt: [$match]");
    }

    my $pager_disable_cmd = 'set cli screen-length 0';

    $ok = $t->print($pager_disable_cmd);
    if (!$ok) {
	$self->log_error("could not send pager disabling command: [$pager_disable_cmd]");
	return 1;
    }

    $self->log_debug("sent pager disable command: [$pager_disable_cmd]");

    if ($match =~ /^\S+>\s$/) {
        $ok = $t->print('configure');
	if (!$ok) {
	    $self->log_error("could not send configure command");
	    return undef;
	}
	
        ($prematch, $match) = $t->waitfor(Match => '/\S+\#\s$/');
	if (!defined($prematch)) {
	    $self->log_error("could not find configure prompt");
	    return undef;
	}

	$self->log_debug("found configure prompt: [$match]");
    }

    if ($match !~ /^(\S+)\#\s$/) {
	$self->log_error("could not match configure command prompt");
	return undef;
    }

    my $prompt = $1;

    $self->{prompt} = $prompt; # save prompt

    $self->log_debug("logged in prompt=[$prompt]");

    $prompt;
}

sub expect_configure_prompt {
    my ($self, $t, $prompt) = @_;

    if (!defined($prompt)) {
	$self->log_error("expect_configure_prompt: internal failure: undefined command prompt");
	return undef;
    }

    my $configure_prompt_regexp = '/' . $prompt . '# $/';

    $configure_prompt_regexp =~ s/\@/\\\@/; # escape @ with \@

    my ($prematch, $match) = $t->waitfor(Match => $configure_prompt_regexp);
    if (defined($prematch)) {
    	$self->log_debug("expect_configure_prompt: found configure prompt: [$match]");
    } else {
	$self->log_error("expect_configure_prompt: could not match configure command prompt: $configure_prompt_regexp");
    }

    ($prematch, $match);
}

sub chat_fetch {
    my ($self, $t, $dev_id, $dev_host, $prompt, $fetch_timeout, $show_cmd, $conf_ref) = @_;
    my $ok;

    my ($prematch, $match);
    
    #($prematch, $match) = $self->expect_configure_prompt($t, $prompt);
    #return unless defined($prematch);

    if ($self->chat_show_conf($t, 'show', $show_cmd)) {
	return 1;
    }

    $self->log_debug("sent show command");

	# Prevent "show" command from appearing in config dump
	#$t->getline();

	# Commment out garbage at top so config file can be restored
	# cleanly at a later date
	#my($line,$top_info);
	#while($line=$t->getline()) {
		# Failsafe: Just in case 'Current configuration'
		# doesn't appear, assume config begins with 'version'
		# or first valid comment.
		#if($line=~/^version / || $line=~/^\!/) {
		#	$top_info.=$line;
	#		last;
#		} else {
#			$top_info.='!!' . $line;
#		}
		# Normally, finding the "Current configuration" line
		# will be enough to exit this loop.
#		last if $line=~/^Current configuration/;
#	}

    my $save_timeout;
    if (defined($fetch_timeout)) {
        $save_timeout = $t->timeout;
        $t->timeout($fetch_timeout);
    }

    ($prematch, $match) = $self->expect_configure_prompt($t, $prompt);
    if (!defined($prematch)) {
	$self->log_error("could not find end of configuration");
	return 1;
    }

    if (defined($fetch_timeout)) {
        $t->timeout($save_timeout);
    }

    $self->log_debug("found end of configuration: [$match]");

#    @$conf_ref = split /\n/, $top_info . $prematch;
    @$conf_ref = split /\n/, $prematch;

    $self->log_debug("fetched: " . scalar @$conf_ref . " lines");

    undef;
}

sub do_fetch {
    my ($self, $file, $line_num, $line, $dev_id, $dev_host, $dev_opt_tab) = @_;

    $self->log_debug("trying");

    my $dev_repository = $self->dev_option($dev_opt_tab, "repository");
    if (!defined($dev_repository)) {
	$self->log_error("undefined repository");
	return;
    }

    if (! -d $dev_repository) {
	$self->log_error("not a directory repository=$dev_repository at file=$file line=$line_num: $line");
	return;
    }

    if (! -w $dev_repository) {
	$self->log_error("unable to write to repository=$dev_repository at file=$file line=$line_num: $line");
	return;
    }

    my $dev_timeout = $self->dev_option($dev_opt_tab, "timeout");

    my $t = new Net::Telnet(Errmode => 'return', Timeout => $dev_timeout);

    my $ok = $t->open($dev_host);
    if (!$ok) {
	$self->log_error("could not connect: $!");
	return;
    }

    $self->log_debug("connected");

    my $prompt = $self->chat_login($t, $dev_id, $dev_host, $dev_opt_tab);

    return unless defined($prompt);

    my @config;

    my $fetch_timeout = $self->dev_option($dev_opt_tab, "fetch_timeout");

    my $show_cmd = $self->dev_option($dev_opt_tab, "show_cmd");

    return if $self->chat_fetch($t, $dev_id, $dev_host, $prompt, $fetch_timeout, $show_cmd, \@config);

    $ok = $t->close;
    if (!$ok) {
	$self->log_error("disconnecting: $!");
    }

    $self->log_debug("disconnected");

    $self->dump_config($dev_id, $dev_opt_tab, \@config);
}

1;
