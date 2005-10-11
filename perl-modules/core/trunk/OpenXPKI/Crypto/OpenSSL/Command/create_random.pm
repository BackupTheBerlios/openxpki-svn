## OpenXPKI::Crypto::OpenSSL::Command::create_random
## (C)opyright 2005 Michael Bell
## $Revision$

use strict;
use warnings;

package OpenXPKI::Crypto::OpenSSL::Command::create_random;

use base qw(OpenXPKI::Crypto::OpenSSL::Command);

sub get_command
{
    my $self = shift;

    my $length = 0;
    if ($self->{RETURN_LENGTH})
    {
        $length = $self->{RETURN_LENGTH};
    }
    if ($self->{RANDOM_LENGTH})
    {
        $length = $self->{RANDOM_LENGTH};
    }
    if (not $length)
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_COMMAND_CREATE_RANDOM_MISSING_LENGTH");
    }

    my $command = "";
    $command .= "rand -base64";
    $command .= " -engine ".$self->{ENGINE}->get_engine()
        if ($self->{ENGINE}->get_engine());
    $command .= " $length";

    return [ $command ];
}

sub hide_output
{
    return 1;
}

sub key_usage
{
    return 0;
}

sub get_result
{
    my $self   = shift;
    my $random = shift;

    ## remove trailing newline
    ## remove trailing =
    $random =~ s/\n//gs;
    $random =~ s/=*$//gs;

    if ($self->{RETURN_LENGTH} and not $self->{RANDOM_LENGTH}) {
        $random = substr ($random, 0, $self->{RETURN_LENGTH});
    }

    if (not defined $random or not length($random))
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_OPENSSL_COMMAND_CREATE_RANDOM_EMPTY");
    }

    return $random;
}

1;
__END__

=head1 Functions

Does this module be up-to-date? Perhaps the engine stuff is a little
bit outdated.

=head2 get_command

Please note that all length specification are bytes. The returned
string only includes base64 characters. It is strongly recommended
to specifiy the required number of secure bytes and not the required
return length.

=over

=item * RETURN_LENGTH

=item * RANDOM_LENGTH

=back

=head2 hide_output

returns true

=head2 key_usage

returns false

=head2 get_result

returns the new passphrase
