#!/usr/bin/perl
# Add -w after perl above for debugging

use File::Copy;			# File::Copy module provides copy & move functions
use strict vars;		# Ensures all variables are declared, as Perl isn't strict

#Don't put the leading slash on the logDir
my $baseDir = "/opt/backup";
my $logDir = $baseDir."/log";
my $configFile = $baseDir."/backup.conf";
my $backupStore = $baseDir."/backup-store/NW-".LocalTime('dom');

my $mailOut = "false";
my $hostName = "localhost";
my $emailTo = "<emailTo>";
my @configContent;
my $errored = "PASSED";
my $stdOut = "";

my $backupHost = "";
my $backupUser = "";
my $backupPassword = "";
my $backupRemoteDir = "/home/remote-backup";

#Create any missing directories for the log file
FileLogger("Script started", "PASSED", "");
FileLogger("Script creating missing directories", "STARTED", "");
if(!-d $logDir)
{
	CreateRecursiveDirectories($logDir);
}
if (!-d $backupStore)
{
	CreateRecursiveDirectories($backupStore);
}
FileLogger("Script creating missing directories", "COMPLETED", "");

#Read configuration file
ReadConfigurationFile($configFile);

FileLogger("Conf file instruction count", @configContent+0, "");

#Process each line and split and then pass to ProcessInstruction
foreach my $line (@configContent)
{
	my @seg;
	$_ = $line;

	($seg[0],$seg[1],$seg[2],$seg[3]) = split(",");
	ProcessInstruction(Trim($seg[0]),Trim($seg[1]),Trim($seg[2]), Trim($seg[3]));
}

#Upload the compressed contents to the server for backup.
FileLogger("Upload compressed contents","STARTED", "");
SecureFTPUnixUpload($backupHost, $backupUser, $backupPassword, $backupRemoteDir, $backupStore, ".tar.gz");


#Finish
FileLogger("Script finished with global status", $errored,"");

sub ProcessInstruction
{
	#void ProcessInstruction(string backup-type, string customlogname, string directory/fileLoc)
	my $complete = 0;

	FileLogger("Processing instruction for $_[1]","STARTED","");

	if ($_[0] eq "FILE")
	{
		system("cp $_[2] $backupStore/ &> $baseDir/stdout") == 0 or $complete = 1;
	}
	elsif ($_[0] eq "DIR")
	{
		system("cp -R $_[2] $backupStore/ &> $baseDir/stdout") == 0 or $complete = 1;
	}
	elsif ($_[0] eq "CMD")
	{
		#Find the special var BACKUP-STORE-DIR and replace with variable value.
		$_[2] =~ s/BACKUP-STORE-DIR/$backupStore/g;

		if ($_[3] eq "YES")
		{
			print "Perl automatically taking input from stdOut\n";
			system("$_[2] &> $baseDir/stdout") == 0 or $complete = 1;
		}
		else
		{
			print "User has defined output in command.\n";
			system($_[2]) == 0 or $complete = 1;
		}

		if ($_[1] eq "COMPRESS-CONTENTS" && $complete == 0)
		{
			#Remove the folder now as the archive is created.
			system("rm -rf ". $backupStore);
		}
	}
	else
	{
		FileLogger("Processing instruction for $_[1]","FAILED","Unknown BACKUP-TYPE detected");
		$complete = 2;
	}

	if($complete == 0)
	{
		FileLogger("Processing instruction for $_[1]","PASSED", ReadStdOutFile());
	}
	elsif ($complete == 1)
	{
		FileLogger("Processing instruction for $_[1]","FAILED", ReadStdOutFile());
		$errored = "FAILED";
	}
}

sub SecureFTPUnixUpload {
	#boolean SecureFTPUnixUpload(string hostName, string userName, string passWord, string changeDir, string filePath, string fileName)
	#Write a script file for lftp -f command on unix
		open(RBFILE, '>', $baseDir.'/rbScript');
		print RBFILE "debug 1\n
					  open sftp://$_[0]\n
					  user \"$_[1]\" \"$_[2]\"\n
					  cd $_[3]\n
					  put $_[4]$_[5]";
		close(RBFILE);

		if (system("lftp -f $baseDir/rbScript") == 0) {
			FileLogger("Upload compressed contents","PASSED", "");
			return 1;
		}
		else {
			FileLogger("Upload compressed contents","FAILED", "Unknown problems please run manually and check configuration");
			return 0;
		}
}

sub ReadStdOutFile
{
	my $output = "";

	if(open (STD_IO, "$baseDir/stdout"))
	{
		while (<STD_IO>)
		{
			$output = $output . $_ . "\n";
		}

		close(STD_IO);
		#Delete stdout file for next output.
		system("rm -f $baseDir/stdout");
	}

	return $output;
}

sub ReadConfigurationFile
{
	my $lineNumber = 0;
	my $line;

	if(open (F_CONFIG, $_[0]))
	{
		FileLogger("Opening conf file","PASSED","");
	}
	else
	{
		FileLogger("Open conf file $_[0]","FAILED", $!);
		$errored = "FAILED";

		#Do this at runtime only if the configuration is not readable.
		$mailOut = "true";
		EmailOut();
		die;
	}

	while (<F_CONFIG>)
	{
		chomp;

		$lineNumber++;
		$line = $_;

		if ($line =~ m/^#/ || $line =~ m/^,/ || $line =~ m/^""/ || $line =~ /^$/)
		{
			#Comment or empty line detected
			#FileLogger("Reading Config File","PASSED","ReadConfigurationFile","", "Read line $lineNumber as Comment or blank");
		}
		else
		{
			#Store the line "as is" for later use
			push(@configContent, $line);
		}
	}
	close(F_CONFIG);
}


sub Trim
{
	# string Trim(string stringToRemoveWhiteSpace)
	# Perl trim function to remove whitespace from the start and end of the string
	my $string = "";
	$string = $_[0];
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

sub CreateRecursiveDirectories
{
	# void CreateRecursiveDirectories(string directoriesToCreate)
	my $dir;
	my $folder = "";

	foreach $dir (split(/\//, $_[0]))
	{
		$folder = "$folder$dir/";
		if($dir ne "") {
			if(!-d "$folder")
			{
				mkdir $folder or
				print "Create $folder directory failed as it didn't exist errored: $@\n" && exit;
			}
			else
			{
				print $folder." directory already exists not re-creating..\n";
			}
		}
	}
}

sub FileLogger
{
	my $fileLog = $logDir."/".LocalTime('now').".log";
	my $tempFileLog = $logDir."/".LocalTime('f').".log";

	if (!-e $fileLog)
	{
		if (open L_FILE, ">>", $fileLog)
		{
			print L_FILE "TIME\tACTION\tOUTCOME\tREASON\n";
			close L_FILE;
		}
		else{open L_FILE, ">>", $tempFileLog}
		{
			print L_FILE "TIME\tACTION\tOUTCOME\tREASON\t";
			close L_FILE;
		}
	}
	if (open L_FILE, ">>", $fileLog){}
	elsif(open L_FILE, ">>", $tempFileLog){}
	else
	{
		print "------------------------------------------------------------------------------------------------------------\n";
		print "Failed to open a file and temp file for logging. Check all directories exist and have write permission on: ". $logDir ."\n";
		print "No directory shown above? Then make sure you have a global \$logDir variable setup in the script.\n";
		print "------------------------------------------------------------------------------------------------------------\n";
	}

	print L_FILE (sprintf LocalTime('f'))."\t$_[0]\t$_[1]\t$_[2]\n";
	print $_[0]." ----> ". $_[1]."\n";

	#Create a string with the stdout output.
	$stdOut = $stdOut . $_[0]." ----> ". $_[1]."\n";
	close L_FILE;
}

sub LocalTime
{
	my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	my @weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
	(my $second, my $minute, my $hour, my $dayOfMonth, my $month, my $yearOffset, my $dayOfWeek, my $dayOfYear, my $daylightSavings) = localtime();
	my $year = 1900 + $yearOffset;
	my $theTime = "$hour:$minute:$second, $weekDays[$dayOfWeek] $months[$month] $dayOfMonth, $year";

	if ($_[0] eq 'f')
	{
		return sprintf("$dayOfMonth-$months[$month]-$year-%02d:%02d:%02d",$hour,$minute,$second);
	}
	elsif ($_[0] eq 'now')
	{
		return "$dayOfMonth-$months[$month]-$year";
	}
	elsif ($_[0] eq 'dom')
	{
		return $dayOfMonth;
	}
}
