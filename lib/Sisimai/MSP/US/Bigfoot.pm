package Sisimai::MSP::US::Bigfoot;
use parent 'Sisimai::MSP';
use feature ':5.10';
use strict;
use warnings;

my $RxMSP = {
    'from'    => qr/[@]bigfoot[.]com[>]/,
    'begin'   => qr/\A\s+[-]+\s*Transcript of session follows/,
    'rfc822'  => qr|\AContent-Type: message/partial|,
    'endof'   => qr/\A__END_OF_EMAIL_MESSAGE__\z/,
    'subject' => qr/\AReturned mail: /,
    'received'=> qr/\w+[.]bigfoot[.]com\b/,
};

sub version     { '4.0.0' }
sub description { 'Bigfoot: http://www.bigfoot.com' }
sub smtpagent   { 'US::Bigfoot' }

sub scan {
    # @Description  Detect an error from Bigfoot
    # @Param <ref>  (Ref->Hash) Message header
    # @Param <ref>  (Ref->String) Message body
    # @Return       (Ref->Hash) Bounce data list and message/rfc822 part
    my $class = shift;
    my $mhead = shift // return undef;
    my $mbody = shift // return undef;
    my $match = 0;

    # $match = 1 if $mhead->{'subject'} =~ $RxMSP->{'subject'};
    $match = 1 if $mhead->{'from'}    =~ $RxMSP->{'from'};
    $match = 1 if grep { $_ =~ $RxMSP->{'received'} } @{ $mhead->{'received'} };
    return undef unless $match;

    my $dscontents = [];    # (Ref->Array) SMTP session errors: message/delivery-status
    my $rfc822head = undef; # (Ref->Array) Required header list in message/rfc822 part
    my $rfc822part = '';    # (String) message/rfc822-headers part
    my $rfc822next = { 'from' => 0, 'to' => 0, 'subject' => 0 };
    my $previousfn = '';    # (String) Previous field name

    my $stripedtxt = [ split( "\n", $$mbody ) ];
    my $recipients = 0;     # (Integer) The number of 'Final-Recipient' header
    my $commandtxt = '';    # (String) SMTP Command name begin with the string '>>>'
    my $esmtpreply = '';    # (String) Reply from remote server on SMTP session
    my $connvalues = 0;     # (Integer) Flag, 1 if all the value of $connheader have been set
    my $connheader = {
        'date'  => '',      # The value of Arrival-Date header
        'lhost' => '',      # The value of Reporting-MTA header
    };

    my $v = undef;
    my $p = '';
    push @$dscontents, __PACKAGE__->DELIVERYSTATUS;
    $rfc822head = __PACKAGE__->RFC822HEADERS;

    require Sisimai::Address;
    for my $e ( @$stripedtxt ) {
        # Read each line between $RxMSP->{'begin'} and $RxMSP->{'rfc822'}.
        $e =~ s{=\d+\z}{};

        if( ( $e =~ $RxMSP->{'rfc822'} ) .. ( $e =~ $RxMSP->{'endof'} ) ) {
            # After "message/rfc822"
            if( $e =~ m/\A([-0-9A-Za-z]+?)[:][ ]*(.+)\z/ ) {
                # Get required headers only
                my $lhs = $1;
                my $rhs = $2;

                $previousfn = '';
                next unless grep { lc( $lhs ) eq lc( $_ ) } @$rfc822head;

                $previousfn  = $lhs;
                $rfc822part .= $e."\n";

            } elsif( $e =~ m/\A[\s\t]+/ ) {
                # Continued line from the previous line
                next if $rfc822next->{ lc $previousfn };
                $rfc822part .= $e."\n" if $previousfn =~ m/\A(?:From|To|Subject)\z/;

            } else {
                # Check the end of headers in rfc822 part
                next unless $previousfn =~ m/\A(?:From|To|Subject)\z/;
                next unless $e =~ m/\A\z/;
                $rfc822next->{ lc $previousfn } = 1;
            }

        } else {
            # Before "message/rfc822"
            next unless ( $e =~ $RxMSP->{'begin'} ) .. ( $e =~ $RxMSP->{'rfc822'} );
            next unless length $e;

            if( $connvalues == scalar( keys %$connheader ) ) {
                # ...
                #
                # Final-Recipient: RFC822; <destinaion@example.net>
                # Action: failed
                # Status: 5.7.1
                # Remote-MTA: DNS; p01c11m075.mx.example.net
                # Diagnostic-Code: SMTP; 553 Invalid recipient destinaion@example.net (Mode: normal)
                # Last-Attempt-Date: Sun, 28 Dec 2014 18:17:16 -0800
                $v = $dscontents->[ -1 ];

                if( $e =~ m/\AFinal-Recipient:[ ]*rfc822;[ ]*([^ ]+)\z/i ) {
                    # Final-Recipient: RFC822; <destinaion@example.net>
                    if( length $v->{'recipient'} ) {
                        # There are multiple recipient addresses in the message body.
                        push @$dscontents, __PACKAGE__->DELIVERYSTATUS;
                        $v = $dscontents->[ -1 ];
                    }
                    $v->{'recipient'} = Sisimai::Address->s3s4( $1 );
                    $recipients++;

                } elsif( $e =~ m/\AAction:[ ]*(.+)\z/i ) {
                    # Action: failed
                    $v->{'action'} = lc $1;

                } elsif( $e =~ m/\AStatus:[ ]*(\d[.]\d+[.]\d+)/i ) {
                    # Status: 5.7.1
                    $v->{'status'} = $1;

                } elsif( $e =~ m/\ARemote-MTA:[ ]*dns;[ ]*(.+)\z/i ) {
                    # Remote-MTA: DNS; p01c11m075.mx.example.net
                    $v->{'rhost'} = lc $1;

                } else {
                    # Get error message
                    if( $e =~ m/\ADiagnostic-Code:[ ]*(.+?);[ ]*(.+)\z/i ) {
                        # Diagnostic-Code: SMTP; 553 Invalid recipient destinaion@example.net (Mode: normal)
                        $v->{'spec'} = uc $1;
                        $v->{'diagnosis'} = $2;

                    } elsif( $p =~ m/\ADiagnostic-Code:[ ]*/i && $e =~ m/\A[\s\t]+(.+)\z/ ) {
                        # Continued line of the value of Diagnostic-Code header
                        $v->{'diagnosis'} .= ' '.$1;
                        $e = 'Diagnostic-Code: '.$e;
                    }
                }

            } else {
                #    ----- Transcript of session follows -----
                # >>> RCPT TO:<destinaion@example.net>
                # <<< 553 Invalid recipient destinaion@example.net (Mode: normal)
                #
                # --201412281816847
                # Content-Type: message/delivery-status
                #
                # Reporting-MTA: dns; litemail57.bigfoot.com
                # Arrival-Date: Sun, 28 Dec 2014 18:17:16 -0800
                #
                if( $e =~ m/\AReporting-MTA:[ ]*dns;[ ]*(.+)\z/i ) {
                    # Reporting-MTA: dns; mx.example.jp
                    next if length $connheader->{'lhost'};
                    $connheader->{'lhost'} = $1;
                    $connvalues++;

                } elsif( $e =~ m/\AArrival-Date:[ ]*(.+)\z/i ) {
                    # Arrival-Date: Wed, 29 Apr 2009 16:03:18 +0900
                    next if length $connheader->{'date'};
                    $connheader->{'date'} = $1;
                    $connvalues++;

                } else {
                    #    ----- Transcript of session follows -----
                    # >>> RCPT TO:<destinaion@example.net>
                    # <<< 553 Invalid recipient destinaion@example.net (Mode: normal)
                    if( $e =~ m/\A[>]{3}[ ]+([A-Z]{4})[ ]?/ ) {
                        # >>> DATA
                        $commandtxt = $1;

                    } elsif( $e =~ m/\A[<]{3}[ ]+(.+)\z/ ) {
                        # <<< Response
                        $esmtpreply = $1;
                    }
                }
            }
        } # End of if: rfc822

    } continue {
        # Save the current line for the next loop
        $p = $e;
        $e = '';
    }

    return undef unless $recipients;
    require Sisimai::String;
    require Sisimai::RFC3463;
    require Sisimai::RFC5322;

    for my $e ( @$dscontents ) {
        # Set default values if each value is empty.
        map { $e->{ $_ } ||= $connheader->{ $_ } || '' } keys %$connheader;

        if( scalar @{ $mhead->{'received'} } ) {
            # Get localhost and remote host name from Received header.
            my $r = $mhead->{'received'};
            $e->{'lhost'} ||= shift @{ Sisimai::RFC5322->received( $r->[0] ) };
            $e->{'rhost'} ||= pop @{ Sisimai::RFC5322->received( $r->[-1] ) };
        }
        $e->{'diagnosis'} =  Sisimai::String->sweep( $e->{'diagnosis'} );
        $e->{'command'} ||= $commandtxt || '';
        $e->{'command'} ||= 'EHLO' if length $esmtpreply;

        if( length( $e->{'status'} ) == 0 || $e->{'status'} =~ m/\A\d[.]0[.]0\z/ ) {
            # There is no value of Status header or the value is 5.0.0, 4.0.0
            my $r = Sisimai::RFC3463->getdsn( $e->{'diagnosis'} );
            $e->{'status'} = $r if length $r;
        }

        $e->{'spec'}  ||= 'SMTP';
        $e->{'agent'} ||= __PACKAGE__->smtpagent;
    }
    return { 'ds' => $dscontents, 'rfc822' => $rfc822part };
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::MSP::US::Bigfoot - bounce mail parser class for C<Bigfoot>.

=head1 SYNOPSIS

    use Sisimai::MSP::US::Bigfoot;

=head1 DESCRIPTION

Sisimai::MSP::US::Bigfoot parses a bounce email which created by C<Bigfoot>.
Methods in the module are called from only Sisimai::Message.

=head1 CLASS METHODS

=head2 C<B<version()>>

C<version()> returns the version number of this module.

    print Sisimai::MSP::US::Bigfoot->version;

=head2 C<B<description()>>

C<description()> returns description string of this module.

    print Sisimai::MSP::US::Bigfoot->description;

=head2 C<B<smtpagent()>>

C<smtpagent()> returns MTA name.

    print Sisimai::MSP::US::Bigfoot->smtpagent;

=head2 C<B<scan( I<header data>, I<reference to body string>)>>

C<scan()> method parses a bounced email and return results as a array reference.
See Sisimai::Message for more details.

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014 azumakuniyuki E<lt>perl.org@azumakuniyuki.orgE<gt>,
All Rights Reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut


