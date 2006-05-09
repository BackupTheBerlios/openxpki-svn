## OpenXPKI::Crypto::Backend::OpenSSL::Command::create_pkcs12
## Written 2005 by Michael Bell for the OpenXPKI project
## Rewritten 2006 by Julia Dubenskaya for the OpenXPKI project
## (C) Copyright 2005-2006 by The OpenXPKI Project
## $Revision$

use strict;
use warnings;

package OpenXPKI::Crypto::Backend::OpenSSL::Command::create_pkcs12;

use base qw(OpenXPKI::Crypto::Backend::OpenSSL::Command);

sub get_command
{
    my $self = shift;

    ## compensate missing parameters

    $self->get_tmpfile ('KEY', 'CERT', 'CHAIN', 'OUT');

    my $engine = "";
    my $engine_usage = $self->{ENGINE}->get_engine_usage();
    $engine = $self->{ENGINE}->get_engine()
        if ($self->{ENGINE}->get_engine() and                                                  
            (($engine_usage =~ m{ ALWAYS }xms) or
             ($engine_usage =~ m{ PRIV_KEY_OPS }xms)));
    $self->{PKCS12_PASSWD} = $self->{PASSWD}
        if (not exists $self->{PKCS12_PASSWD});
    $self->{ENC_ALG} = "aes256" if (not exists $self->{ENC_ALG});

    ## check parameters

    if (not $self->{KEY})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_COMMAND_CREATE_PKCS12_MISSING_KEY");
    }
    if (not $self->{CERT})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_COMMAND_CREATE_PKCS12_MISSING_CERT");
    }
    if (not exists $self->{PASSWD})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_COMMAND_CREATE_PKCS12_MISSING_PASSWD");
    }
    if (not length ($self->{PASSWD}))
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_COMMAND_CREATE_PKCS12_EMPTY_PASSWD");
    }
    if (length ($self->{PKCS12_PASSWD}) < 4)
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_COMMAND_CREATE_PKCS12_PASSWD_TOO_SHORT");
    }
    if ($self->{ENC_ALG} ne "aes256" and
        $self->{ENC_ALG} ne "aes192" and
        $self->{ENC_ALG} ne "aes128" and
        $self->{ENC_ALG} ne "idea" and
        $self->{ENC_ALG} ne "des3" and
        $self->{ENC_ALG} ne "des")
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_COMMAND_CREATE_RSA_WRONG_ENC_ALG");
    }

    ## prepare data

    $self->write_file (FILENAME => $self->{KEYFILE},
                       CONTENT  => $self->{KEY},
	               FORCE    => 1);
    $self->write_file (FILENAME => $self->{CERTFILE},
                       CONTENT  => $self->{CERT},
	               FORCE    => 1);
    $self->write_file (FILENAME => $self->{CHAINFILE},
                       CONTENT  => $self->{CHAIN},
	               FORCE    => 1)
        if ($self->{CHAIN});

    ## build the command

    my $command  = "pkcs12 -export";
    $command .= " -engine $engine" if ($engine);
    $command .= " -inkey ".$self->{KEYFILE};
    $command .= " -in ".$self->{CERTFILE};
    $command .= " -out ".$self->{OUTFILE};
    $command .= " -".$self->{ENC_ALG};
    if ($self->{CHAIN})
    {
        $command .= " -certfile ".$self->{CHAIN};
    }
    elsif ($self->{INTERNAL_CHAIN})
    {
        $command .= " -certfile ".$self->{INTERNAL_CHAIN};
    }

    $command .= " -passin env:pwd";
    $self->set_env ("pwd" => $self->{PASSWD});

    $command .= " -passout env:p12pwd";
    $self->set_env ('p12pwd' => $self->{PKCS12_PASSWD});

    return [ $command ];
}

sub hide_output
{
    return 0;
}

## please notice that key_usage means usage of the engine's key
sub key_usage
{
    my $self = shift;
    return 1;
}

sub get_result
{
    my $self = shift;
    return $self->read_file ($self->{OUTFILE});
}

1;
__END__

=head1 Functions

=head2 get_command

Only the engine is optional all other parameters must be present.
This function was only designed for normal certificates. They are
not designed for the tokens themselves.

=over

=item * KEY

=item * ENGINE_USAGE

=item * PASSWD

=item * CERT

=item * PKCS12_PASSWD (optional)

If you do not specify this option then we use PASSWD to encrypt the new
PKCS#12 file.

=item * ENC_ALG (optional)

=item * INTERNAL_CHAIN (optional)

=back

=head2 hide_output

returns false

=head2 key_usage

returns true (FIXME: does this be correct?)

=head2 get_result

returns the newly created PKCS#12 container
