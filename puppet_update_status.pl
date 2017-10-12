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
my $nodeDirectory = "/opt/puppetlabs/server/data/puppetserver/yaml/node";
my $smtpSender = "foreman\@debian1.ukmtest.local";
my $smtpServer = "127.0.0.1";

# execution
# first get all recipients from files, sort and uniq
my @reportRecipients;
my @reportFiles = <$nodeDirectory/*.yaml>;
foreach my $reportFile (@reportFiles) {
	my $nodeConfig = LoadFile($reportFile);
	my $contactMail = $nodeConfig->{classes}->{updatereport}->{contactmail};
	push (@reportRecipients, $contactMail);
}
@reportRecipients = sort(uniq(@reportRecipients));

# now iterate over recipients and create report per recipient
my %reports;
foreach my $reportContact (@reportRecipients) {

	# iterate over report files (machines)
	foreach my $reportFile (@reportFiles) {
		my $nodeConfig = LoadFile($reportFile);

		# if machine belongs to recipient
		if ( $nodeConfig->{classes}->{updatereport}->{contactmail} eq $reportContact ) {
			# collect common information
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
			# apt knows updates and security-updates
			# check for apt-like system (Debian and derivates)
			if ( $reports{$reportContact}{$nodeConfig->{name}}{machinePkg} eq "apt" ) {

				# if "has_updates" is true, it has updates, list them
				if ( $nodeConfig->{parameters}->{apt_has_updates} == 1 ) {
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					my $list = join(" ",@{$nodeConfig->{parameters}->{apt_package_updates}});
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = $list;
				# if not, not ;)
				} else {
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "empty";
				}

				# if "has_updates" is true, there maybe security updates, also
				# (apt-plugin dont sned this facts if no normal updates are available)
				if ( $nodeConfig->{parameters}->{apt_has_updates} == 1 ) {
					# if "has_security_updates" is true, it has updates, list them
					if ( $nodeConfig->{parameters}->{apt_security_updates} > 0 ) {
						$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "true";
						my $list = join(" ",@{$nodeConfig->{parameters}->{apt_package_security_updates}});
						$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = $list;
					# if not, not ;)
					} else {
						$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "false";
						$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = "empty";
					}

				# if "has_updates" false, there are no security updates, so set list and value manually
				} else {
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = "empty";
				}
			}

			# collect pkg dependent information: YUM
			# yum knows updates and security-updates
			# check for yum-like system (RedHat an derivates)
			if ( $reports{$reportContact}{$nodeConfig->{name}}{machinePkg} eq "yum" ) {

				# if "yum_updates_available" is true, it has updates, list them
				if ( $nodeConfig->{parameters}->{yum_updates_available} eq "yes" ) {
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = $nodeConfig->{parameters}->{yum_updates_available_list};
				# if not, not ;)
				} else {
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "empty";
				}

				# if "yum_updates_available_security" is true, it has updates, list them
				if ( $nodeConfig->{parameters}->{yum_updates_available_security} eq "yes" ) {
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = $nodeConfig->{parameters}->{yum_updates_available_security_list};
				# if not, not ;)
				} else {
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = "empty";
				}
			}

			# collect pkg dependent information: Zypper (security patches are security updates, normal patches are updates, updates are updates)
			# zypper knows updates, patches and security-patches
			# check for zypper-like system (Suse)
			if ( $reports{$reportContact}{$nodeConfig->{name}}{machinePkg} eq "zypper" ) {

				# if "zypper_updates_available" is true, it has updates, list them
				if ( $nodeConfig->{parameters}->{zypper_updates_available} eq "yes" ) {
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "Updates: ".$nodeConfig->{parameters}->{zypper_updates_available_list};
				# if not, not ;)
				} else {
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "Updates: empty";
				}

				# if "zypper_patches_available" is true, it has patches, list them
				if ( $nodeConfig->{parameters}->{zypper_patches_available} eq "yes" ) {
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = $reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList}.", Patches: ".$nodeConfig->{parameters}->{zypper_patches_available_list};
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} =~ s/ , /, /g;
				# if not, not ;)
				} else {
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = $reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList}.", Patches: empty";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} =~ s/ , /, /g;
				}

				# if "zypper_patches_available_security" is true, it has patches, list them
				if ( $nodeConfig->{parameters}->{zypper_patches_available_security} eq "yes" ) {
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = $nodeConfig->{parameters}->{zypper_patches_available_security_list};
				# if not, not ;)
				} else {
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = "empty";
				}
			}

			# collect pkg dependent information: PKG (no difference between normal and security, so just copy)
			# this is still very basic, because we dont get any updates without subscription - UNTESTED!
			# check for pkg-like system (Solaris)
			if ( $reports{$reportContact}{$nodeConfig->{name}}{machinePkg} eq "pkg" ) {
				# if "pkg_updates_available" is true, it has updates, list them
				if ( $nodeConfig->{parameters}->{pkg_updates_available} eq "yes" ) {
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "unknown";
				# if not, not ;)
				} else {
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "empty";
				}

				# set updates-security to values of updates
				$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = $reports{$reportContact}{$nodeConfig->{name}}{hasUpdates};
				$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = $reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList};

			}
		}
	}
}

# now create report emails by contact
foreach my $reportContact (@reportRecipients) {

	# create reporting file, open handler and print preamble
	my $reportFilename = '/tmp/puppet-report-mail-'.$reportContact.'.txt';
	my $reportAvailable = 0;
	open(my $reportFilenameHandle, '>', $reportFilename) or die "Could not open file '$reportFilename' $!";
	print $reportFilenameHandle "Update status report for:\t".$reportContact."\n";
	print $reportFilenameHandle "Report generation date:\t\t".localtime."\n\n";
	print $reportFilenameHandle "Your machines:";

	# list machines contact is responsible 
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

	# now iterate over machines for this contact and create per machine report
	for my $reportMachine ( keys %{ $reports{$reportContact}} ) {
		my %reportData = %{ $reports{$reportContact}{$reportMachine}};

		# test if needs reporting for updates
		my $createReport = 0;
		if ( $reportData{hasUpdates} eq "true" ) {
			$createReport = 1;
			$reportAvailable = 1;
		}

		# test if needs reporting for security updates
		my $createSecurityReport = 0;
		if ( $reportData{hasSecurityUpdates} eq "true" ) {
			$createSecurityReport = 1;
			$reportAvailable = 1;
		}
	
		# print report by machine
		if ( $reportData{reportAlways} == 1 || $createReport == 1 || $createSecurityReport == 1 ) {

			# machine information
			print $reportFilenameHandle "Machine:\t".$reportData{machineFqdn}."\n";
			print $reportFilenameHandle "System:\t\t".$reportData{machineOsName}." ".$reportData{machineOsVersion}.", up since ".$reportData{machineUptime}." days, last report on ".localtime($reportData{lastUpdate}).", IP: ".$reportData{machineIp}."\n";
			print $reportFilenameHandle "Maintainer:\t".$reportData{machineOwnerName}." <".$reportData{machineOwnerMail}.">\n";

			# if no updates at all, print message
			if ( $createReport == 0 && $createSecurityReport == 0 ) {
				print $reportFilenameHandle "\t\tNo updates are available, everything is fine, just chill and relax!\n";
			} else {
				# if normal updates are available, print report
				if ( $createReport == 1 ) {
					print $reportFilenameHandle "Updates:\t$reportData{hasUpdatesList}\n";
				} 

				# if security updates are available, print report
				if ( $createSecurityReport == 1 ) {
					print $reportFilenameHandle "Security:\t$reportData{hasSecurityUpdatesList}\n";
				}
			}
			print $reportFilenameHandle "\n";
		}
	}

	# if no updates on any machine available, print message
	if ( $reportAvailable == 0 ) {
		print $reportFilenameHandle "There are no updates for your systems, just relax and enjoy your day!\n\n";
	}

	# postamble and end of report file
	print $reportFilenameHandle "That's it, my dark master,\nlive long and prosper!\n\nMaster of puppets\n".hostname."\n";
	close($reportFilenameHandle);

	# create emailbody from reportfile and delete reportfile
	open($reportFilenameHandle, '<:encoding(UTF-8)', $reportFilename) or die "Could not open file '$reportFilename' $!";
	my $mailBody = "";
	while (my $row = <$reportFilenameHandle>) {
		$mailBody .= $row;
	}
	close($reportFilenameHandle);
	unlink($reportFilename);

	# define emailtransport
	my $transport = Email::Sender::Transport::SMTP->new({
		host => $smtpServer
	});

	# create email and send
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
