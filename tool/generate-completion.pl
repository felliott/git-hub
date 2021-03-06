#!/usr/bin/env perl

use strict;

sub main {
    my ($cmd) = @_;
    my $input = do { local $/; <> };
    my $input2 = do { local $/; <> };
    my ($options_spec) = $input2 =~ m/ ^ OPTIONS_SPEC="\\ $ (.*?) ^ " $/xsm;
    $options_spec =~ s/.*Options:\n--//s;

    my %functions;
    my @options;
    for my $line (split m/\n/, $options_spec) {
        next unless $line =~ m/\S/;
        my $arg = 0;
        my ($key, $desc) = split ' ', $line, 2;
        if ($key =~ s/=$//) {
            $arg = 1;
        }
        my @keys = split m/,/, $key;
        my $function_name;
        if ($key eq "remote") {
            $function_name = "_git-hub-complete-remote";
            my $function = {
                name => $function_name,
                command => "git remote",
            };
            $functions{ $key } = $function;
        }
        push @options, {
            keys => \@keys,
            arg => $arg,
            desc => $desc,
            function_name => $function_name,
        };
    }

    $input =~ s/.*?\n= Commands\n//s;
    $input =~ s/(.*?\n== Configuration Commands\n.*?\n)==? .*/$1/s;
    my @list;
    my @repo_cmds;
    while ($input =~ s/.*?^- (.*?)(?=\n- |\n== |\z)//ms) {
        my $text = $1;
        $text =~ /\A(.*)\n/
            or die "Bad text '$text'";
        my $usage = $1;
        $usage =~ s/\A`(.*)`\z/$1/
            or die "Bad usage: '$text'";
        (my $name = $usage) =~ s/ .*//;
        push @list, $name;
        if ($usage =~ m#\Q$name\E \(?\[?(<owner>/)?\]?<repo>#) {
            push @repo_cmds, $name;
        }
    }
    @repo_cmds = sort @repo_cmds;
    @list = sort @list;

    if ($cmd eq "bash") {
        generate_bash(\@list, \@repo_cmds, \@options, \%functions);
    }
    else {
        generate_zsh(\@list, \@repo_cmds, \@options, \%functions);
    }
}

sub generate_zsh {
    my ($list, $repo_cmds, $options, $functions) = @_;

    my $options_string = '';
    for my $opt (@$options) {
        my $keys = $opt->{keys};
        my $desc = $opt->{desc};
        my $function = $opt->{function_name};
        $desc =~ s/'/'"'"'/g;
        # examples:
        #'(-c --count)'{-c,--count}'[Number of list items to show]:count' \
        #'--remote[Remote name (like "origin")]:remote' \
        my $arg = '';
        if ($opt->{arg}) {
            $arg = ":$keys->[0]";
        }
        else {
            $arg .= ":";
        }
        if ($function) {
            $arg .= ":$function";
        }
        my @keystrings = map { (length $_ > 1 ? "--" : "-") . $_ } @$keys;
        if (@$keys == 1) {
            $options_string .= sprintf "        '%s[%s]%s' \\\n",
                $keystrings[0], $desc, $arg;
        }
        elsif (@$keys > 1) {
            $options_string .= sprintf "        '(%s)'{%s}'[%s]%s' \\\n",
                (join ' ', @keystrings), (join ',', @keystrings), $desc, $arg;
        }
    }

    my $function_list = '';
    for my $key (sort keys %$functions) {
        my $function = $functions->{ $key };
        my $name = $function->{name};
        my $cmd = $function->{command};
        my $body = <<"...";
$name() {
    local dynamic_comp
    IFS=\$'\\n' set -A  dynamic_comp `$cmd`
    compadd -X "$key:" \$dynamic_comp
}
...
        $function_list .= "$body\n";
    }

    print <<'...';
#compdef git-hub -P git\ ##hub
#description perform GitHub operations

# DO NOT EDIT. This file generated by tool/generate-completion.pl.

if [[ -z $GIT_HUB_ROOT ]]; then
	echo 'GIT_HUB_ROOT is null; has `/path/to/git-hub/.rc` been sourced?'
	return 3
fi

_git-hub() {
    typeset -A opt_args
    local curcontext="$curcontext" state line context

    _arguments -s \
        '1: :->subcmd' \
        '2: :->repo' \
...
    print $options_string;
    print <<'...';
        && ret=0

    case $state in
    subcmd)
...
    print <<"...";
        compadd @$list
    ;;
    repo)
        case \$line[1] in
...
    print " " x 8;
    print join '|', @$repo_cmds;
    print <<"...";
)
            if [[ \$line[2] =~ "^((\\w|-)+)/(.*)" ]];
            then
                local username="\$match[1]"
                if [[ "\$username" != "\$__git_hub_lastusername" ]];
                then
                    __git_hub_lastusername=\$username
                    IFS=\$'\\n' set -A  __git_hub_reponames `git hub repos \$username --raw`
                fi
                compadd -X "Repos:" \$__git_hub_reponames
            else
                _arguments "2:Repos:()"
            fi
        ;;
        config|config-unset)
            local config_keys
            IFS=\$'\\n' set -A config_keys `git hub config-keys`
            compadd -X "Config keys:" \$config_keys
        ;;
        help)
            compadd @$list
        ;;
        esac
    ;;
    esac

}

$function_list
...
}

sub generate_bash {
    my ($list, $repo_cmds, $options, $functions) = @_;

    my $options_string = '';
    for my $opt (@$options) {
        my $keys = $opt->{keys};
        my $arg = '';
        if ($opt->{arg}) {
            $arg = "=";
        }
        my @keystrings = map { (length $_ > 1 ? "--" : "-") . $_ } @$keys;
        for my $key (@keystrings) {
            $options_string .= " $key$arg";
        }
    }

    my @function_list;
    for my $key (sort keys %$functions) {
        my $function = $functions->{ $key };
        my $name = $function->{name};
        my $cmd = $function->{command};
        my $body = <<"...";
[[ \$last == "--$key" || \$cur =~ ^--$key= ]]; then
            local dynamic_comp=`$cmd`
            __gitcomp "\$dynamic_comp" "" "\${cur##--$key=}"
            return
...
        push @function_list, $body;
    }
    my $indent = " " x 8;
    my $function_list = "${indent}if "
        . join ("\n${indent}elsif ", @function_list)
        . "${indent}fi";

    print <<"...";
#!bash

# DO NOT EDIT. This file generated by tool/generate-completion.pl.

_git_hub() {
    local _opts="$options_string"
    local subcommands="@$list"
    local subcommand="\$(__git_find_on_cmdline "\$subcommands")"

    if [ -z "\$subcommand" ]; then
        # no subcommand yet
        case "\$cur" in
        -*)
            __gitcomp "\$_opts"
        ;;
        *)
            __gitcomp "\$subcommands"
        esac

    else

        # dynamic completions
        local last=\${COMP_WORDS[ \$COMP_CWORD-1 ]}

$function_list

        case "\$cur" in

        -*)
            __gitcomp "\$_opts"
            return
        ;;

        *)
            if [[ \$subcommand == help ]]; then
                __gitcomp "\$subcommands"
            elif [[ \$subcommand == "config" || \$subcommand == "config-unset" ]]; then
                local config_keys
                config_keys=`git hub config-keys`
                __gitcomp "\$config_keys"
            fi
        ;;

        esac

    fi
}
...
}

main(shift);
