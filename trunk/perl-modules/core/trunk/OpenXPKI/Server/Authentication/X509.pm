## OpenXPKI::Server::Authentication::X509.pm 
##
## Written 2006 by Michael Bell
## (C) Copyright 2006 by The OpenXPKI Project
## $Revision$

use strict;
use warnings;

package OpenXPKI::Server::Authentication::X509;

use OpenXPKI::Debug 'OpenXPKI::Server::Authentication::X509';
use OpenXPKI::Exception;
use OpenXPKI::Server::Context qw( CTX );

## constructor and destructor stuff

sub new {
    my $that = shift;
    my $class = ref($that) || $that;

    my $self = {};

    bless $self, $class;

    my $keys = shift;
    ##! 1: "start"

    my $config = CTX('xml_config');
    $self->{CHAIN} = $config->get_xpath (XPATH   => [ %{$keys->{XPATH}},   "chain" ],
                                         COUNTER => [ %{$keys->{COUNTER}}, 0 ]);

    return $self;
}

sub login
{
    my $self = shift;
    ##! 1: "start"
    my $gui = CTX('service');

    ##! 2: "type ... x509"

    my $challenge = CTX('session')->get_id();
    my $signature = $gui->get_x509_login ($challenge);

    my $token = CTX('crypto_layer')->get_token
                (
                    TYPE      => "DEFAULT",
                    PKI_REALM => CTX('session')->get_pki_realm()
                );

    my $sig = OpenXPKI::Crypto::PKCS7->new (TOKEN => $token,
                                            PKCS7 => $signature);
    $self->{USER} = $sig->verify (CONTENT => $challenge,
                                  CHAIN   => $self->{CHAIN});
    return 1;
}

sub get_user
{
    my $self = shift;
    ##! 1: "start"
    return $self->{USER};
}

sub get_role
{
    my $self = shift;
    ##! 1: "start"
    ## how should we determine the role ???
    return $self->{USER};
}

1;
__END__

=head1 Description

This is the class which supports OpenXPKI with a signature based
authentication method. The parameters are passed as a hash reference.
Actually the role mapping does not work.
FIXME:
Does it be possible to search an LDAP directory for certificates?
How can we find a certificate in our database if we do not know the PKI
Realm and the CA certificate? If we know the database entry then we know
the role of the certificate.
IDEA: search all certs with this serial
NEXT: scan for a matching cert
NEXT: PKI Realm allowed for authentication
NEXT: use role from database

=head1 Functions

=head2 new

is the constructor. The supported parameters are XPATH and COUNTER.
This is the minimum parameter set for any authentication class.
The only parsed argument form the configuration is the used chain.
This is used to support certificates from other CAs.

=head2 login

returns true if the login was successful.

=head2 get_user

returns the user which logged in successful.

=head2 get_role

returns the user (no typo today) which logged in successful.
