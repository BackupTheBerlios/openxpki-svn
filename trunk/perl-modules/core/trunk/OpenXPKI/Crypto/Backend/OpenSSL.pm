## OpenXPKI::Crypto::Backend::OpenSSL
## Written 2005 by Michael Bell
## (C)opyright 2005-2006 OpenXPKI
## $Revision$
	
use strict;
use warnings;
use utf8; ## pack/unpack is too slow

package OpenXPKI::Crypto::Backend::OpenSSL;

use OpenXPKI::Crypto::Backend::OpenSSL::Shell;
use OpenXPKI::Crypto::Backend::OpenSSL::Command;
use OpenXPKI::Server::Context qw( CTX );

use OpenXPKI qw(debug);
use OpenXPKI::Exception;
use English;

use File::Spec;
use Date::Parse;
use DateTime;

# use Smart::Comments;

sub new
{
    my $that = shift;
    my $class = ref($that) || $that;

    my $self = {DEBUG => 0};
    bless $self, $class;

    my $keys = shift;
    $self->{DEBUG} = 1 if ($keys->{DEBUG});

    # determine temporary directory to use:
    # if a temporary directoy is specified, use it
    # else try /var/tmp (because potentially large files may be written that
    # are better left in the /var file system)
    # if /var/tmp does not exist fallback to /tmp

    ## removed FileSpec because it returns relative paths!!!

    my $requestedtmp = $keys->{TMP};
    delete $keys->{TMP};
  CHECKTMPDIRS:
    for my $path ($requestedtmp,    # user's preference
		  File::Spec->catfile('', 'var', 'tmp'), # suitable for large files
		  File::Spec->catfile('', 'tmp'),        # present on all UNIXes
	) {

	# directory must be readable & writable to be usable as tmp
	if (defined $path &&
	    (-d $path) &&
	    (-r $path) &&
	    (-w $path)) {
	    $self->{TMP} = $path;
	    last CHECKTMPDIRS;
	}
    }

    if (! (exists $self->{TMP} && -d $self->{TMP}))
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_TEMPORARY_DIRECTORY_UNAVAILABLE");
    }

    $self->__load_config  ($keys);
    $self->__init_engine  ();
    $self->__init_shell   ();
    $self->__init_command ();

    return $self;
}

sub __load_config
{
    my $self = shift;
    my $keys = shift;

    my $name        = $keys->{NAME};
    my $realm_index = $keys->{PKI_REALM_INDEX};
    my $type_path   = $keys->{TOKEN_TYPE};
    my $type_index  = $keys->{TOKEN_INDEX};

    $self->{PARAMS}->{TMP} = $self->{TMP};

    # any existing key in this hash is considered optional in %token_args
    my %is_optional = ();

    # default tokens don't need key, cert etc...
    if ($type_path eq "common") {
	foreach (qw(key cert internal_chain passwd passwd_parts)) {
	    $is_optional{uc($_)}++;
	}
    }

    # FIXME: currently unused attributes:
    # openca-sv
    foreach my $key (qw(debug      backend       mode 
                        engine     shell         wrapper 
                        randfile
                        key        cert          internal_chain
                        passwd     passwd_parts 
                       )) {

	my $attribute_count;
	eval {
	    $self->debug ("try to get attribute_count");
	    $attribute_count = CTX('xml_config')->get_xpath_count (
		XPATH    => [ 'pki_realm', $type_path, 'token', $key ],
		COUNTER  => [ $realm_index, $type_index, 0 ]);
	    $self->debug ("attribute_count ::= ".$attribute_count);
	};

	if (my $exc = OpenXPKI::Exception->caught())
	{
	    $self->debug ("caught exception while reading config attribute $key");
	    # only pass exception if attribute is not optional
	    if (! $is_optional{uc($key)}) {
		$self->debug ("argument $key is not optional, escalating");
		OpenXPKI::Exception->throw (
		    message => "I18N_OPENXPKI_CRYPTO_TOKENMANAGER_ADD_TOKEN_INCOMPLETE_CONFIGURATION",
		    child   => $exc,
		    params  => {"NAME" => $name, 
				"TYPE" => $type_path, 
				"ATTRIBUTE" => $key,
		    },
		    );
	    }
	    $attribute_count = 0;
	}
        elsif ($EVAL_ERROR)
        {
	    $self->debug ("caught system exception while reading config attribute $key");
	    # FIXME: should we really throw an OpenXPKI exception here?
            OpenXPKI::Exception->throw (message => $EVAL_ERROR);
        }

	# multivalue attributes are not desired/supported
	if ($attribute_count > 1) {
	    OpenXPKI::Exception->throw (
		message => "I18N_OPENXPKI_CRYPTO_BACKEND_OPENSSL_LOAD_CONFIG_DUPLICATE_ATTRIBUTE",
		params  => {"NAME" => $name, 
			    "TYPE" => $type_path, 
			    "ATTRIBUTE" => $key,
		});
	}

	if ($attribute_count == 1) {
	    my $value = CTX('xml_config')->get_xpath (
		XPATH    => [ 'pki_realm', $type_path, 'token', $key ],
		COUNTER  => [ $realm_index, $type_index, 0, 0 ]);

	    $self->{PARAMS}->{uc($key)} = $value;
	}
    }
    return 1;
}

sub __init_engine
{
    my $self = shift;
    my $keys = shift;

    if (!exists $self->{PARAMS}->{ENGINE} || $self->{PARAMS}->{ENGINE} eq "") {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_ENGINE_UNDEFINED",
	    );
    }

    my $engine = "OpenXPKI::Crypto::Backend::OpenSSL::Engine::".$self->{PARAMS}->{ENGINE};
    eval "use $engine;";
    if ($@)
    {
        my $msg = $@;
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_INIT_ENGINE_USE_FAILED",
            params  => {"ERRVAL" => $msg});
    }
    delete $self->{PARAMS}->{ENGINE};
    $self->{ENGINE} = eval {$engine->new (%{$self->{PARAMS}})};
    if (my $exc = OpenXPKI::Exception->caught())
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_INIT_ENGINE_NEW_FAILED",
            child   => $exc);
    } elsif ($EVAL_ERROR) {
        $EVAL_ERROR->rethrow();
    }
    return 1;
}

sub __init_shell
{
    my $self = shift;

    if (not -x $self->{PARAMS}->{SHELL})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_BINARY_NOT_FOUND");
    } else {
        $self->{OPENSSL} = $self->{PARAMS}->{SHELL};
        $self->{SHELL}   = $self->{PARAMS}->{SHELL};
    }
    my $wrapper = $self->{ENGINE}->get_wrapper();
    if ($wrapper)
    {
        $self->{SHELL} = $wrapper . " " . $self->{OPENSSL};
    }

    eval
    {
        $self->{SHELL} = OpenXPKI::Crypto::Backend::OpenSSL::Shell->new (
                             ENGINE => $self->{ENGINE},
                             DEBUG  => $self->{DEBUG},
                             SHELL  => $self->{SHELL},
                             TMP    => $self->{TMP});
    };
    if (my $exc = OpenXPKI::Exception->caught())
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_INIT_SHELL_FAILED",
            child   => $exc);
    } elsif ($EVAL_ERROR) {
        $EVAL_ERROR->rethrow();
    }

    return 1;
}

sub __init_command
{
    my $self = shift;

    foreach my $key (["TMP", "TMP"], ["RANDFILE", "RANDOM_FILE"])
    {
        if (not exists $self->{PARAMS}->{$key->[0]})
        {
            OpenXPKI::Exception->throw (
                message => "I18N_OPENXPKI_CRYPTO_OPENSSL_MISSING_COMMAND_PARAM",
                params  => {"PARAM" => $key->[0]});
        }
        $self->{COMMAND_PARAMS}->{$key->[1]} = $self->{PARAMS}->{$key->[0]};
    }

    return 1;
}

sub command
{
    my $self = shift;
    my $keys = shift;

    my $cmd  = "OpenXPKI::Crypto::Backend::OpenSSL::Command::".$keys->{COMMAND};
    delete $keys->{COMMAND};
    $self->debug ("Command: $cmd");

    my $ret = eval
    {
        my $cmdref = $cmd->new (%{$self->{COMMAND_PARAMS}}, %{$keys},
                                ENGINE => $self);
        my $cmds = $cmdref->get_command();

        $self->{SHELL}->start();
        $self->{SHELL}->init_engine($self->{ENGINE}) if ($self->{ENGINE}->get_engine());
        $self->{SHELL}->run_cmd ($cmds);
        $self->{SHELL}->stop();
        my $result = $self->{SHELL}->get_result();
        $result = $cmdref->get_result ($result);

        if ($cmdref->hide_output())
        {
            $self->debug ("successfully completed");
        } else {
            $self->debug ("successfully completed: $result");
        }

        $cmdref->cleanup();
        return $result;
    };
    if (my $exc = OpenXPKI::Exception->caught())
    {
        $self->{SHELL}->stop(); ## this is safe
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_COMMAND_FAILED",
            params  => {"COMMAND" => $cmd},
            child   => $exc);
    } elsif ($EVAL_ERROR) {
        $EVAL_ERROR->rethrow();
    } else {
        return $ret;
    }
}

sub get_object
{
    my $self = shift;
    my $keys = shift;

    my $previous_debug = undef;
    if ($keys->{DEBUG})
    {
        $previous_debug = $self->{DEBUG};
        $self->{DEBUG} = $keys->{DEBUG};
    }

    my $format = ($keys->{FORMAT} or "PEM");
    my $data   = $keys->{DATA};
    my $type   = $keys->{TYPE};

    $self->debug ("format: $format") if($format);
    $self->debug ("data:   $data");
    $self->debug ("type:   $type");

    my $object = undef;
    if ($type eq "X509")
    {
        if ($format eq "DER")
        {
            $object = OpenXPKI::Crypto::Backend::OpenSSL::X509::_new_from_der ($data);
        } else {
            $object = OpenXPKI::Crypto::Backend::OpenSSL::X509::_new_from_pem ($data);
        }
    } elsif ($type eq "CSR")
    {
        if ($format eq "DER")
        {
            $object = OpenXPKI::Crypto::Backend::OpenSSL::PKCS10::_new_from_der ($data);
        }
        elsif ($format eq "SPKAC")
        {
            #$data =~ s/.*SPKAC\s*=\s*([^\s\n]*).*/$1/s;
            #$self->debug ("spkac is ".$data);
            #$self->debug ("length of spkac is ".length($data));
            #$self->debug ("data is ".$data);
            $object = OpenXPKI::Crypto::Backend::OpenSSL::SPKAC::_new ($data);
        } else {
            $object = OpenXPKI::Crypto::Backend::OpenSSL::PKCS10::_new_from_pem ($data);
        }
    } elsif ($type eq "CRL")
    {
        if ($format eq "DER")
        {
            $object = OpenXPKI::Crypto::Backend::OpenSSL::CRL::_new_from_der ($data);
        } else {
            $object = OpenXPKI::Crypto::Backend::OpenSSL::CRL::_new_from_pem ($data);
        }
    } else {
        $self->{DEBUG} = $previous_debug if ($keys->{DEBUG});
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_GET_OBJECT_UNKNOWN_TYPE",
            params  => {"TYPE" => $type});
    }
    if (not $object)
    {
        $self->{DEBUG} = $previous_debug if ($keys->{DEBUG});
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_GET_OBJECT_NO_REF");
    }

    $self->debug ("returning object");

    $self->{DEBUG} = $previous_debug if ($keys->{DEBUG});
    return $object;
}

sub get_object_function
{
    my $self   = shift;
    my $keys   = shift;
    my $previous_debug = undef;
    if ($keys->{DEBUG})
    {
        $previous_debug = $self->{DEBUG};
        $self->{DEBUG} = $keys->{DEBUG};
    }
    my $object = $keys->{OBJECT};
    my $func   = $keys->{FUNCTION};
    $self->debug ("object:   $object");
    $self->debug ("function: $func");

    if ($func eq "free")
    {
        $self->{DEBUG} = $previous_debug if ($keys->{DEBUG});
        return $self->free_object ($object);
    }

    my $result = $object->$func();
    ##without pack/unpack the conversion does not work
    ##utf8::upgrade($result) if (defined $result);
    $result = pack "U0C*", unpack "C*", $object->$func();

    ## fix proprietary "DirName:" of OpenSSL
    if (defined $result and $func eq "extensions")
    {
        my @lines = split /\n/, $result;
        $result = "";
        foreach my $line (@lines)
        {
            if ($line !~ /^\s*DirName:/)
            {
                $result .= $line."\n";
            } else {
                my ($name, $value) = ($line, $line);
                $name  =~ s/^(\s*DirName:).*$/$1/;
                $value =~ s/^\s*DirName:(.*)$/$1/;
                my $dn = OpenXPKI::DN::convert_openssl_dn ($value);
                $result .= $name.$dn."\n";
            }
        }
    }

    ## parse dates
    if (defined $result && (($func eq "notbefore") || ($func eq "notafter"))) {

	# seconds since the epoch
	my $epoch = str2time($result);
	if (! defined $epoch) {
	    OpenXPKI::Exception->throw (
		message => "I18N_OPENXPKI_CRYPTO_OPENSSL_GET_OBJECT_FUNCTION_DATE_PARSING_ERROR",
		params  => {
		    DATE => $result,
		},
		);
	}
	
	my $dt_object = DateTime->from_epoch(epoch => $epoch);

	# make sure we use UTC
	$dt_object->set_time_zone('UTC');

	$result = $dt_object;
    }
    
    $self->{DEBUG} = $previous_debug if ($keys->{DEBUG});
    return $result;
}

sub free_object
{
    my $self   = shift;
    my $object = shift;
    $object->free();
    return 1;
}

our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;
    $AUTOLOAD =~ s/^.*://;
    if (not $self->{ENGINE})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_AUTOLOAD_MISSING_ENGINE",
            params  => {"FUNCTION" => $AUTOLOAD});
    }
    if ($AUTOLOAD eq "online" or
        $AUTOLOAD eq "login" or
        $AUTOLOAD eq "get_mode" or
        $AUTOLOAD eq "get_keyfile" or
        $AUTOLOAD eq "get_certfile" or
        $AUTOLOAD eq "get_chainfile" or
        $AUTOLOAD eq "get_engine" or
        $AUTOLOAD eq "get_keyform" or
        $AUTOLOAD eq "get_passwd")
    {
        return  $self->{ENGINE}->$AUTOLOAD (@_);
    }
    OpenXPKI::Exception->throw (
        message => "I18N_OPENXPKI_CRYPTO_OPENSSL_AUTOLOAD_MISSING_FUNCTION",
        params  => {"FUNCTION" => $AUTOLOAD});
}

sub DESTROY
{
    my $self = shift;
    return;
}

1;
__END__

=head1 Description

This is the basic class to provide OpenXPKI with an OpenSSL based
cryptographic token. Beside the documented function all functions
in the class OpenXPKI::Crypto::Backend::OpenSSL::Engine are
available here too because we map these engine specific functions
directly to the engine (via AUTOLOAD).

=head1 Functions

=head2 new

is the constructor. It requires five basic parameters which are
described here. The other parameters are engine specific and
are described in the related engine documentation. Please see
OpenXPKI::Crypto::Backend::OpenSSL::Engine for more details.

=over

=item * RANDFILE (file to store the random informations)

=item * DEBUG (switch on or off debugging)

=item * SHELL (the OpenSSL binary)

=item * TMP (the used temporary directory which must be private)

=back

=head2 command

execute an OpenSSL command. You must specify the name of the command
as first parameter followed by a hash with parameter. Example:

  $token->command ({COMMAND => "create_key", TYPE => "RSA", ...});

=head2 get_object

is used to get access to a cryptographic object. The following objects
are supported today:

=over

=item * SPKAC

=item * PKCS10

=item * X509

=item * CRL

=back

You must specify the type of the object in the parameter TYPE. Additionally
you must specify the format if several different formats are supported. If
you do not do this then PEM is assumed. The most important parameter is
DATA which contains the plain object data which must be parsed.

The returned value can be a scalar or a reference. You must not use this value
directly. You have to use the functions get_object_function or free_object
to access the object.

=head2 get_object_function

is used to execute functions on the object. The function expects two
parameters the OBJECT and the FUNCTION which should be called. All
functions have no parameters. The result of the function will be
returned.

When parsing an X.509 certificate the NotBefore and NotAfter dates are
returned as hash references containing the following keys:
  raw         => date as returned by the OpenSSL parser
  epoch       => seconds since the epoch
  object      => blessed DateTime object with TimeZone set to UTC
  iso8601     => string containing the ISO8601 formatted date (UTC)
  openssltime => string containing an OpenSSL compatible date string (UTC)

=head2 free_object

frees the object internally. The only parameter is the object which
was returned by get_object.
