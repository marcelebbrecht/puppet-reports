#!/usr/bin/perl

# includes
use strict;
use warnings;
use YAML::XS 'LoadFile';
use Data::Dumper;
use List::MoreUtils qw(any uniq);
use Sys::Hostname;
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP ();
use Email::Simple ();
use Email::Simple::Creator ();

# settings
my $debug = 0;
my $nodeDirectory = "/opt/puppetlabs/server/data/puppetserver/yaml/node";
my $smtpSender = "foreman\@debian1.ukmtest.local";
my $smtpServer = "127.0.0.1";

# execution
# first get all recipients, sort and uniq
my @reportRecipients;
my @reportFiles = <$nodeDirectory/*.yaml>;
foreach my $reportFile (@reportFiles) {
	my $nodeConfig = LoadFile($reportFile);
	my $contactMail = $nodeConfig->{classes}->{updatereport}->{contactmail};
	push (@reportRecipients, $contactMail);
}
@reportRecipients = sort(uniq(@reportRecipients));

my %reports;
# now iterate over hosts and create report per recipient
foreach my $reportContact (@reportRecipients) {
	if ( $debug > 0 ) { print "Report for: ".$reportContact."\n"; }
	foreach my $reportFile (@reportFiles) {
		if ( $debug > 0 ) { print "\tTesting: ".$reportFile."\n"; }
		my $nodeConfig = LoadFile($reportFile);
		if ( $debug > 0 ) { print "\tTesting: ".$nodeConfig->{name}."\n"; }
		if ( $debug > 0 ) { print "\tTesting: ".$nodeConfig->{classes}->{updatereport}->{contactmail}."\n"; }
		if ( $nodeConfig->{classes}->{updatereport}->{contactmail} eq $reportContact ) {
			# collect common information
			if ( $debug > 0 ) { print "\t\tFound machine: ".$nodeConfig->{name}."\n"; }
			$reports{$reportContact}{$nodeConfig->{name}}{contactMail} = $nodeConfig->{classes}->{updatereport}->{contactmail};
			$reports{$reportContact}{$nodeConfig->{name}}{contactName} = $nodeConfig->{classes}->{updatereport}->{contactname};
			$reports{$reportContact}{$nodeConfig->{name}}{reportAlways} = $nodeConfig->{classes}->{updatereport}->{reportalways};
			$reports{$reportContact}{$nodeConfig->{name}}{lastUpdate} = (stat($reportFile))[9];
			$reports{$reportContact}{$nodeConfig->{name}}{machineName} = $nodeConfig->{name};
			$reports{$reportContact}{$nodeConfig->{name}}{machineEnvironment} = $nodeConfig->{parameters}->{environment};
			$reports{$reportContact}{$nodeConfig->{name}}{machineOwnerName} = $nodeConfig->{parameters}->{owner_name};
			$reports{$reportContact}{$nodeConfig->{name}}{machineOwnerMail} = $nodeConfig->{parameters}->{owner_email};
			$reports{$reportContact}{$nodeConfig->{name}}{machinePuppetVersion} = $nodeConfig->{parameters}->{puppetversion};
			$reports{$reportContact}{$nodeConfig->{name}}{machineFqdn} = $nodeConfig->{parameters}->{fqdn};
			$reports{$reportContact}{$nodeConfig->{name}}{machineIp} = $nodeConfig->{parameters}->{ipaddress};
			$reports{$reportContact}{$nodeConfig->{name}}{machineOsName} = $nodeConfig->{parameters}->{operatingsystem};
			$reports{$reportContact}{$nodeConfig->{name}}{machineOsVersion} = $nodeConfig->{parameters}->{operatingsystemrelease};
			$reports{$reportContact}{$nodeConfig->{name}}{machinePkg} = $nodeConfig->{parameters}->{package_provider};
			$reports{$reportContact}{$nodeConfig->{name}}{machineUptime} = $nodeConfig->{parameters}->{uptime_days};
			$reports{$reportContact}{$nodeConfig->{name}}{foremanHostgroup} = $nodeConfig->{parameters}->{hostgroup};

			# collect pkg dependent information: APT
			if ( $debug > 0 ) { print "\n"; }
			if ( $debug > 0 ) { print "\t\tTesting: ".$reports{$reportContact}{$nodeConfig->{name}}{machinePkg}." == apt\n"; }
			if ( $reports{$reportContact}{$nodeConfig->{name}}{machinePkg} eq "apt" ) {
				if ( $debug > 0 ) { print "\t\tTesting: is APT!\n"; }

				if ( $debug > 0 ) { print "\t\tTesting: has updates: ".$nodeConfig->{parameters}->{apt_has_updates}."\n"; }
				if ( $nodeConfig->{parameters}->{apt_has_updates} == 1 ) {
					if ( $debug > 0 ) { print "\t\thas updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					my $list = join(" ",@{$nodeConfig->{parameters}->{apt_package_updates}});
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = $list;
				} else {
					if ( $debug > 0 ) { print "\t\tno updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "empty";
				}

				if ( $nodeConfig->{parameters}->{apt_has_updates} == 1 ) {
					if ( $debug > 0 ) { print "\t\tTesting: has security updates: ".$nodeConfig->{parameters}->{apt_security_updates}."\n"; }
					if ( $nodeConfig->{parameters}->{apt_security_updates} > 0 ) {
						if ( $debug > 0 ) { print "\t\thas security updates!\n"; }
						$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "true";
						my $list = join(" ",@{$nodeConfig->{parameters}->{apt_package_security_updates}});
						$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = $list;
					} else {
						if ( $debug > 0 ) { print "\t\tno security updates!\n"; }
						$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "false";
						$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = "empty";
					}
				} else {
					if ( $debug > 0 ) { print "\t\tno security updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = "empty";
				}
			}

			# collect pkg dependent information: YUM
			if ( $debug > 0 ) { print "\n"; }
			if ( $debug > 0 ) { print "\t\tTesting: ".$reports{$reportContact}{$nodeConfig->{name}}{machinePkg}." == yum\n"; }
			if ( $reports{$reportContact}{$nodeConfig->{name}}{machinePkg} eq "yum" ) {
				if ( $debug > 0 ) { print "\t\tTesting: is YUM!\n"; }

				if ( $debug > 0 ) { print "\t\tTesting: has updates: ".$nodeConfig->{parameters}->{yum_updates_available}."\n"; }
				if ( $nodeConfig->{parameters}->{yum_updates_available} eq "yes" ) {
					if ( $debug > 0 ) { print "\t\thas updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = $nodeConfig->{parameters}->{yum_updates_available_list};
				} else {
					if ( $debug > 0 ) { print "\t\tno updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "empty";
				}

				if ( $debug > 0 ) { print "\t\tTesting: has security updates: ".$nodeConfig->{parameters}->{yum_updates_available_security}."\n"; }
				if ( $nodeConfig->{parameters}->{yum_updates_available_security} eq "yes" ) {
					if ( $debug > 0 ) { print "\t\thas security updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = $nodeConfig->{parameters}->{yum_updates_available_security_list};
				} else {
					if ( $debug > 0 ) { print "\t\tno security updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = "empty";
				}
			}

			# collect pkg dependent information: Zypper (security patches are security updates, normal patches are updates, updates are updates)
			if ( $debug > 0 ) { print "\n"; }
			if ( $debug > 0 ) { print "\t\tTesting: ".$reports{$reportContact}{$nodeConfig->{name}}{machinePkg}." == zypper\n"; }
			if ( $reports{$reportContact}{$nodeConfig->{name}}{machinePkg} eq "zypper" ) {
				if ( $debug > 0 ) { print "\t\tTesting: is Zypper!\n"; }

				if ( $debug > 0 ) { print "\t\tTesting: has updates: ".$nodeConfig->{parameters}->{zypper_updates_available}."\n"; }
				if ( $nodeConfig->{parameters}->{zypper_updates_available} eq "yes" ) {
					if ( $debug > 0 ) { print "\t\thas updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "Updates: ".$nodeConfig->{parameters}->{zypper_updates_available_list};
				} else {
					if ( $debug > 0 ) { print "\t\tno updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "Updates: empty";
				}

				if ( $debug > 0 ) { print "\t\tTesting: has patches: ".$nodeConfig->{parameters}->{zypper_patches_available}."\n"; }
				if ( $nodeConfig->{parameters}->{zypper_patches_available} eq "yes" ) {
					if ( $debug > 0 ) { print "\t\thas patches!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = $reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList}.", Patches: ".$nodeConfig->{parameters}->{zypper_patches_available_list};
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} =~ s/ , /, /g;
				} else {
					if ( $debug > 0 ) { print "\t\tno patches!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = $reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList}.", Patches: empty";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} =~ s/ , /, /g;
				}

				if ( $debug > 0 ) { print "\t\tTesting: has security patches: ".$nodeConfig->{parameters}->{zypper_patches_available_security}."\n"; }
				if ( $nodeConfig->{parameters}->{zypper_patches_available_security} eq "yes" ) {
					if ( $debug > 0 ) { print "\t\thas security patches!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = $nodeConfig->{parameters}->{zypper_patches_available_security_list};
				} else {
					if ( $debug > 0 ) { print "\t\tno security patches!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = "empty";
				}
			}

			# collect pkg dependent information: PKG (no difference between normal and security, so just copy)
			if ( $debug > 0 ) { print "\n"; }
			if ( $debug > 0 ) { print "\t\tTesting: ".$reports{$reportContact}{$nodeConfig->{name}}{machinePkg}." == pkg\n"; }
			if ( $reports{$reportContact}{$nodeConfig->{name}}{machinePkg} eq "pkg" ) {
				if ( $debug > 0 ) { print "\t\tTesting: is PKG!\n"; }

				if ( $debug > 0 ) { print "\t\tTesting: has updates: ".$nodeConfig->{parameters}->{pkg_updates_available}."\n"; }
				if ( $nodeConfig->{parameters}->{pkg_updates_available} eq "yes" ) {
					if ( $debug > 0 ) { print "\t\thas updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "unknown";
				} else {
					if ( $debug > 0 ) { print "\t\tno updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "empty";
				}

				$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = $reports{$reportContact}{$nodeConfig->{name}}{hasUpdates};
				$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = $reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList};

			}
		} else {
			if ( $debug > 0 ) { print "\t\tUnknown machine: ".$nodeConfig->{name}."\n"; }
		}
		if ( $debug > 0 ) { print "\n\n"; }
	}
	if ( $debug > 0 ) { print "\n\n"; }
}

# now create report emails by contact
if ( $debug > 0 ) { print "\n\n"; }
foreach my $reportContact (@reportRecipients) {
	# create reporting file and open handler
	if ( $debug > 0 ) { print "Create report for user: ".$reportContact."\n"; }
	my $reportFilename = '/tmp/puppet-report-mail-'.$reportContact.'.txt';
	my $reportAvailable = 0;
	open(my $reportFilenameHandle, '>', $reportFilename) or die "Could not open file '$reportFilename' $!";
	print $reportFilenameHandle "Update status report for:\t".$reportContact."\n";
	print $reportFilenameHandle "Report generation date:\t\t".localtime."\n\n";
	print $reportFilenameHandle "Your machines:";

	my $firstmachine = 1;
	for my $reportMachine ( keys %{ $reports{$reportContact}} ) {
		my %reportData = %{ $reports{$reportContact}{$reportMachine}};
		if ( $firstmachine == 1 ) {
			print $reportFilenameHandle "\t".$reportData{machineFqdn}."\n";
			$firstmachine = 0;
		} else {
			print $reportFilenameHandle "\t\t".$reportData{machineFqdn}."\n";
		}
	}
	print $reportFilenameHandle "\n";

	for my $reportMachine ( keys %{ $reports{$reportContact}} ) {
		my %reportData = %{ $reports{$reportContact}{$reportMachine}};

		# test if needs reporting for updates
		my $createReport = 0;
	        if ( $debug > 0 ) { print "\t\tTest for updates: ".$reportMachine."\n"; }
		if ( $reportData{hasUpdates} eq "true" ) {
		        if ( $debug > 0 ) { print "\t\tHas updates!\n"; }
			$createReport = 1;
			$reportAvailable = 1;
		} else {
		        if ( $debug > 0 ) { print "\t\tHas no updates!\n"; }
		}

		# test if needs reporting for security updates
		my $createSecurityReport = 0;
	        if ( $debug > 0 ) { print "\t\tTest for security updates: ".$reportMachine."\n"; }
		if ( $reportData{hasSecurityUpdates} eq "true" ) {
		        if ( $debug > 0 ) { print "\t\tHas security updates!\n"; }
			$createSecurityReport = 1;
			$reportAvailable = 1;
		} else {
		        if ( $debug > 0 ) { print "\t\tHas no security updates!\n"; }
		}
	
		if ( $reportData{reportAlways} == 1 || $createReport == 1 || $createSecurityReport == 1 ) {
	        	if ( $debug > 0 ) { print "\tCreate report for machine: ".$reportMachine."\n"; }

		        if ( $debug > 1 ) { print "\t\tWriting report file\n"; }
			print $reportFilenameHandle "Machine:\t".$reportData{machineFqdn}."\n";
			print $reportFilenameHandle "System:\t\t".$reportData{machineOsName}." ".$reportData{machineOsVersion}.", up since ".$reportData{machineUptime}." days, last report on ".localtime($reportData{lastUpdate}).", IP: ".$reportData{machineIp}."\n";
			print $reportFilenameHandle "Maintainer:\t".$reportData{machineOwnerName}." <".$reportData{machineOwnerMail}.">\n";
			if ( $createReport == 0 && $createSecurityReport == 0 ) {
				print $reportFilenameHandle "\t\tNo updates are available, everything is fine, just chill and relax!\n";
			} else {
				if ( $createReport == 1 ) {
					print $reportFilenameHandle "Updates:\t$reportData{hasUpdatesList}\n";
				} 
				if ( $createSecurityReport == 1 ) {
					print $reportFilenameHandle "Security:\t$reportData{hasSecurityUpdatesList}\n";
				}
			}
			print $reportFilenameHandle "\n";
		} else {
	        	if ( $debug > 0 ) { print "\tNo report for machine: ".$reportMachine."\n"; }
		}
	}

	if ( $debug > 0 ) { print "Testing for available updates on user: ".$reportContact."\n"; }
	if ( $reportAvailable == 0 ) {
		if ( $debug > 0 ) { print "Updates available on user: ".$reportContact."\n"; }
		print $reportFilenameHandle "There are no updates for your systems, just relax and enjoy your day!\n\n";
	} else {
		if ( $debug > 0 ) { print "No updates available on user: ".$reportContact."\n"; }
	}

	print $reportFilenameHandle "That's it, my dark master,\nlive long and prosper!\n\nMaster of puppets\n".hostname."\n";
	close($reportFilenameHandle);

	open($reportFilenameHandle, '<:encoding(UTF-8)', $reportFilename) or die "Could not open file '$reportFilename' $!";
	my $mailBody = "";
	while (my $row = <$reportFilenameHandle>) {
		$mailBody .= $row;
	}
	close($reportFilenameHandle);
	unlink($reportFilename);

	if ( $debug > 1 ) { print "\tSending emailreport to: ".$reportContact."\n"; }
	my $transport = Email::Sender::Transport::SMTP->new({
		host => $smtpServer
	});

	my $email = Email::Simple->create(
		header => [
			To => $reportContact,
			From => $smtpSender,
			Subject => "Update status report for: ".$reportContact,
		],
		body => $mailBody."\n",
	);
	sendmail($email, { transport => $transport });
}

if ( $debug > 1 ) { 
	print "\nReport Data:\n";
	print Dumper(%reports);
	print "\n";
}
