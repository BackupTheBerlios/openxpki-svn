## OpenXPKI::Crypto::CSR
## (C)opyright 2003-2005 Michael Bell
## $Revision$

use strict;
use warnings;

package OpenXPKI::Crypto::CSR;

use OpenXPKI::DN;
use Math::BigInt;

use base qw(OpenXPKI::Crypto::Object);

sub new
{
    my $self = shift;
    my $class = ref($self) || $self;
    $self = {};
    bless $self, $class;

    my $keys = { @_ };
    $self->{DEBUG}  = 1 if ($keys->{DEBUG});
    $self->{DATA}   = $keys->{DATA};
    $self->{TOKEN}  = $keys->{TOKEN};
    $self->{FORMAT} = $keys->{FORMAT};

    if (not $self->{DATA})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_CSR_NEW_MISSING_DATA");
    }
    if (not $self->{TOKEN})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_CSR_NEW_MISSING_TOKEN");
    }
    if (not $self->{TYPE})
    {
        if ($self->{DATA} =~ /^-----BEGIN/m)
        {
            $self->{TYPE} = "PKCS10";
        } else {
            $self->{TYPE} = "SPKAC";
        }
    }
    if ($self->{TYPE} ne "PKCS10" and $self->{TYPE} ne "SPKAC")
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_CSR_NEW_WRONG_TYPE",
            params  => {"TYPE" => $self->{TYPE}});
    }

    $self->__init();

    return $self;
}

sub __init
{
    my $self = shift;
    $self->debug ("entering function");

    ##########################
    ##     init objects     ##
    ##########################

    $self->{header} = OpenXPKI::Crypto::Header->new (DEBUG => $self->{DEBUG},
                                                     DATA  => $self->{DATA});
    $self->{PARSED}->{HEADER} = $self->{header}->get_parsed();
    if (not $self->{header}->get_body())
    {
        $self->{TYPE} = "HEADER" if ($self->{header}->get_body());
        return 1;
    }
    $self->{csr} = $self->{TOKEN}->get_object({DEBUG  => $self->{DEBUG},
                                               DATA   => $self->{header}->get_body(),
                                               TYPE   => "CSR",
                                               FORMAT => $self->{TYPE}});

    ##########################
    ##     core parsing     ##
    ##########################

    my @attrlist;
    if ($self->{TYPE} eq "SPKAC")
    {
        @attrlist = ("pubkey", "keysize", "pubkey_algorithm", "exponent", "modulus",
                     "pubkey_hash", "signature_algorithm");
    } else {
        @attrlist = ("subject", "version", "signature_algorithm",
                     "pubkey", "pubkey_hash", "keysize", "pubkey_algorithm",
                     "exponent", "modulus", "extensions");
    }
    foreach my $attr (@attrlist)
    {
        $self->{PARSED}->{BODY}->{uc($attr)} = $self->{TOKEN}->get_object_function ({
                                                   DEBUG    => $self->{DEBUG},
                                                   OBJECT   => $self->{csr},
                                                   FUNCTION => $attr});
    }
    $self->{TOKEN}->free_object ($self->{csr});
    delete $self->{csr};
    $self->debug ("loaded CSR attributes");
    my $ret = $self->{PARSED}->{BODY};

    ###########################
    ##     parse subject     ##
    ###########################
 
    ## handle some missing data for SPKAC request
    if ( $self->{TYPE} eq "SPKAC" ) {
        my @reqLines = split /\n/, $self->getBody();
        $ret->{SUBJECT} = "";
	for my $tmp (@reqLines)
        {
            $tmp =~ s/\r$//;
            my ($key,$val)=($tmp =~ /([\w]+)\s*=\s*(.*)\s*/ );
            if ($key =~ /SPKAC/i)
            {
                $ret->{SPKAC} = $val;
            } else {
                $ret->{SUBJECT} .= ", " if ($ret->{SUBJECT});
                $ret->{SUBJECT} .= "$key=$val";
            }
        }
        $ret->{VERSION}	= 1;
    }

    ## the subject in the header is more important
    if ($self->{PARSED}->{HEADER}->{SUBJECT}) {
        $self->{PARSED}->{SUBJECT} = $self->{PARSED}->{HEADER}->{SUBJECT};
    } else {
        $self->{PARSED}->{SUBJECT} = $ret->{SUBJECT};
    }
    $self->debug ("SUBJECT: ".$self->{PARSED}->{SUBJECT});

    ## load the differnt parts of the DN into DN_HASH
    if ($ret->{SUBJECT})
    {
        my $obj = OpenXPKI::DN->new ($ret->{SUBJECT});
        %{$ret->{SUBJECT_HASH}} = $obj->get_hashed_content();
    } else {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_CSR_INIT_MISSING_SUBJECT");
    }

    ##################################
    ##     parse emailaddresses     ##
    ##################################

    ## set emailaddress

    $self->{PARSED}->{EMAILADDRESSES} = [ $self->get_emails ($ret) ];
    $self->{PARSED}->{EMAILADDRESS} = $ret->{EMAILADDRESSES}->[0];

    $self->debug ("SUBJECT_ALT_NAME: ".$self->{PARSED}->{HEADER}->{SUBJECT_ALT_NAME})
        if ($self->{PARSED}->{HEADER}->{SUBJECT_ALT_NAME});
    $self->debug ("EMAILADDRESS: ".$self->{PARSED}->{EMAILADDRESS})
        if ($self->{PARSED}->{EMAILADDRESS});


    ###############################
    ##     extension parsing     ##
    ###############################

    return 1 if (not $ret->{EXTENSIONS});

    ## load all extensions
    $ret->{PLAIN_EXTENSIONS} = $ret->{EXTENSIONS};
    delete $ret->{EXTENSIONS};
    $ret->{OPENSSL_EXTENSIONS} = {};

    my ($val, $key);
    my @lines = split(/\n/, $ret->{PLAIN_EXTENSIONS});

    my $i = 0;
    while($i < @lines)
    {
        if ($lines[$i] =~ /^\s*([^:]+):\s*(?:critical|)\s*$/i)
        {
            $key = $1;
            $ret->{OPENSSL_EXTENSIONS}->{$key} = [];
            $i++;
            while(exists $lines[$i] and $lines[$i] !~ /^\s*[^:]+:\s*(?:critical|)\s*$/ && $i < @lines)
            {
                $val = $lines[$i];
                $val =~ s/^\s+//;
                $val =~ s/\s+$//;
                $i++;
                next if $val =~ /^$/;
                push(@{$ret->{OPENSSL_EXTENSIONS}->{$key}}, $val);
            }
        } else {
            ## FIXME: can this every happen?
            $i++;
        }
    }

    $self->debug ("show all extensions and their values");
    while(($key, $val) = each(%{$ret->{OPENSSL_EXTENSIONS}}))
    {
        $self->debug ("found extension: $key");
        $self->debug ("with value(s): $_") foreach(@{$val});
    }

    return 1;
}

sub get_serial
{
    my $self = shift;
    return $self->{PARSED}->{HEADER}->{SERIAL};
}

sub get_emails
{
    my $self = shift;
    my $parsed = $self->{PARSED};
    $parsed = shift if ($_[0]);

    my @emails = ();

    ## extract emails from subject alt name

    if ( $parsed->{HEADER}->{SUBJECT_ALT_NAME} ) {
        my @subjectAltNames = split (/,\s*/, $parsed->{HEADER}->{SUBJECT_ALT_NAME});
        foreach my $h (@subjectAltNames) {
            next if ($h !~ /^\s*email(|\.[0-9]+)[:=]/is);
            $h =~ s/^\s*email(|\.[0-9]+)[:=]//i;
            push (@emails, $h);
        }
    }

    ## extract emails from subject

    ## pkcs#9 emailAddress
    if (exists $parsed->{SUBJECT_HASH}->{EMAILADDRESS})
    {
        foreach my $mail (@{$parsed->{SUBJECT_HASH}->{EMAILADDRESS}})
        {
            push @emails, $mail;
        }
    }
    ## rfc822Mailbox
    if (exists $parsed->{SUBJECT_HASH}->{MAIL})
    {
        foreach my $mail (@{$parsed->{SUBJECT_HASH}->{MAIL}})
        {
            push @emails, $mail;
        }
    }

    return @emails;
}

sub get_converted
{
    my $self   = shift;
    my $format = shift;

    if ($self->{TYPE} eq "SPKAC")
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_CSR_GET_CONVERTED_SPKAC_DETECTED");
    }
    if (not $format)
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_CSR_GET_CONVERTED_MISSING_FORMAT");
    }
    if ($format ne "PEM" and $format ne "DER" and $format ne "TXT")
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_CSR_GET_CONVERTED_WRONG_FORMAT",
            params  => {"FORMAT" => $format});
    }

    if ($format eq 'PEM' ) {
        return $self->get_body();
    }
    else
    {
        return $self->{TOKEN}->command ({COMMAND => "convert_pkcs10",
                                         DATA    => $self->get_body(),
                                         OUT     => $format});
    }
}

1;
__END__

=head1 Description

This is the module for managing CSRs. You can use this module to parse
and convert CSRs. If you are missing some functions here please check
OpenXPKI::Crypto::Object. OpenXPKI::Crypto::Object inherits from
OpenXPKI::Crypto::Object several functions.

=head1 Functions

=head2 new

The constructor support four option - DEBUG, DATA, FORMAT and TOKEN.
DEBUG is a true or false value which activates or deactivates the debugging.
FORMAT is optional but can be specified. It can be set to PKCS10 or
SPKAC. If the FORMAT is missing then the module tries to determine the
type of the request from DATA with some REGEX. DATA is a the CSR.
Please note that even PKCS#10 requests are only supported in PEM format.
TOKEN is a token from the token manager (OpenXPKI::TokenManager).
The token is needed to parse the requests.

=head2 get_serial

returns the serial of the CSR. The serial will be extracted from the
header.

=head2 get_converted

The functions supports three formats - PEM, DER and TXT. All other
formats create errors (or better exceptions). The CSR will be
returned in the specified format on success. This functionality
is only supported for PKCS#10 requests. If you try this with a SPKAC
request then an exception will occur.

=head2 get_emails

returns an array with all available email addresses. Pleae note that
this include PKCS#9 emailAddress, rfc822Mailbox and the subject
alternative name email extensions.
