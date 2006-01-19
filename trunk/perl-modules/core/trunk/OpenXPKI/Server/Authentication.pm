## OpenXPKI::Server::Authentication.pm 
##
## Written by Michael Bell 2003
## Copyright (C) 2003-2006 by The OpenXPKI Project
## $Revision$

use strict;
use warnings;
use utf8;

package OpenXPKI::Server::Authentication;

use English;
use OpenXPKI qw(debug);
use OpenXPKI::Exception;
use OpenXPKI::Server::Context qw( CTX );

use OpenXPKI::Server::Authentication::Anonymous;
use OpenXPKI::Server::Authentication::External;
use OpenXPKI::Server::Authentication::LDAP;
use OpenXPKI::Server::Authentication::Password;
use OpenXPKI::Server::Authentication::X509;

## constructor and destructor stuff

sub new {
    my $that = shift;
    my $class = ref($that) || $that;

    my $self = {
                DEBUG     => 0,
               };

    bless $self, $class;

    my $keys = { @_ };
    $self->{DEBUG}       = 1 if ($keys->{DEBUG});
    $self->debug ("start");

    return undef if (not $self->__load_config ());

    $self->debug ("end");
    return $self;
}

#############################################################################
##                         load the configuration                          ##
##                            (caching support)                            ##
#############################################################################

sub __load_config
{
    my $self = shift;
    $self->debug ("start");

    ## load all PKI realms

    my $realms = CTX('xml_config')->get_xpath_count (XPATH => 'pki_realm');
    for (my $i=0; $i < $realms; $i++)
    {
        $self->__load_pki_realm ({PKI_REALM => $i});
    }

    $self->debug ("leaving function successfully");
    return 1;
}

sub __load_pki_realm
{
    my $self  = shift;
    my $keys  = shift;
    my $realm = $keys->{PKI_REALM};

    my $name = CTX('xml_config')->get_xpath (XPATH   => ['pki_realm', 'name'],
                                         COUNTER => [$realm, 0]);
    $self->{PKI_REALM}->{$name}->{POS} = $realm;

    ## load all handlers

    my $handlers = CTX('xml_config')->get_xpath_count (XPATH   => ['pki_realm', 'auth', 'handler'],
                                                   COUNTER => [$realm, 0]);
    for (my $i=0; $i < $handlers; $i++)
    {
        $self->__load_handler ({PKI_REALM => $name, HANDLER => $i});
    }

    ## determine all authentication stacks

    my $stacks = CTX('xml_config')->get_xpath_count (XPATH   => ['pki_realm', 'auth', 'stack'],
                                                 COUNTER => [$realm, 0]);
    for (my $i=0; $i < $stacks; $i++)
    {
        $self->__load_stack ({PKI_REALM => $name, STACK => $i});
    }
    return 1;
}

sub __load_stack
{
    my $self  = shift;
    my $keys  = shift;
    my $realm     = $keys->{PKI_REALM};
    my $realm_pos = $self->{PKI_REALM}->{$realm}->{POS};
    my $stack_pos = $keys->{STACK};

    ## load stack name (this is what the user will see)

    my $stack = CTX('xml_config')->get_xpath (XPATH   => ['pki_realm', 'auth', 'stack', 'name'],
                                          COUNTER => [$realm_pos, 0, $stack_pos, 0]);

    ## determine all used handlers

    $self->{PKI_REALM}->{$realm}->{STACK}->{$stack} =
        CTX('xml_config')->get_xpath_list (XPATH   => ['pki_realm', 'auth', 'stack', 'handler'],
                                       COUNTER => [$realm_pos, 0, $stack_pos]);
    return 1;
}

sub __load_handler
{
    my $self  = shift;
    my $keys  = shift;
    my $realm       = $keys->{PKI_REALM};
    my $realm_pos   = $self->{PKI_REALM}->{$realm}->{POS};
    my $handler_pos = $keys->{HANDLER};

    ## load handler name and type

    my $name = CTX('xml_config')->get_xpath (XPATH   => ['pki_realm', 'auth', 'handler', 'name'],
                                         COUNTER => [$realm_pos, 0, $handler_pos, 0]);
    my $type = CTX('xml_config')->get_xpath (XPATH   => ['pki_realm', 'auth', 'handler', 'type'],
                                         COUNTER => [$realm_pos, 0, $handler_pos, 0]);
    $self->debug ("name ::= $name");
    $self->debug ("type ::= $type");
    $type = "OpenXPKI::Server::Authentication::$type";
    $self->{PKI_REALM}->{$name}->{HANDLER}->{$name} = eval {

        $type->new ({DEBUG   => $self->{DEBUG},
                     XPATH   => ['pki_realm', 'auth', 'handler'],
                     COUNTER => [$realm_pos, 0, $handler_pos]});

                                                           };
    if ($EVAL_ERROR)
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_AUTHENTICATION_LOAD_HANDLER_FAILED",
            child   => $EVAL_ERROR);
    }

    return 1;
}

########################################################################
##                          identify the user                         ##
########################################################################

sub login
{
    my $self = shift;
    my $keys = shift;

    $self->debug ("Starting authentication ... ");

    $keys->{SESSION}->start_authentication();

    my $realm = $keys->{SESSION}->get_pki_realm();
    my $stack = CTX('gui')->get_authentication_stack ({
                    STACKS => {%{$self->{PKI_REALM}->{$realm}->{STACK}}}
                                                      });

    my $ok = 0;
    foreach my $handler (@{$self->{PKI_REALM}->{$realm}->{STACK}->{$stack}})
    {
        my $ref = $self->{PKI_REALM}->{$realm}->{HANDLER}->{$handler};
        eval
        {
            $ref->login();
        };
        if (not $EVAL_ERROR)
        {
            $ok = 1;
            $keys->{SESSION}->set_user ($ref->get_user());
            $keys->{SESSION}->set_role ($ref->get_role());
            $keys->{SESSION}->finish_authentication();
            last;
        }
    }
    if (not $ok)
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_AUTHENTICATION_LOGIN_FAILED");
    }

    return 1;
}

1;