#!/usr/bin/perl -w
#Sample command: updatePhysXOnGitHub.pl -physx=3.3 -subversion=3.3.3 -destination=F:\Github\downloads
#If don't input "-physx" parameter, the default physx is 3.3;
#If don't input "-destination" parameter, the default is $Bin;
#If you want to download results from mirrorartifact, you can set "-mirror=1", otherwise default is 1.
#If you want to download results with multi-threaded tool from mirrorartifact, you can set "-multi=1", otherwise default is 1.

use strict;
use FindBin qw($Bin);
use Data::Dumper;
use File::Basename qw(basename);
use Getopt::Long;

use lib "$Bin/../../extlib";
use lib "$Bin/../../lib";
use NVIDIA::SysUtils;
use NVIDIA::TeamCity::API::Project;
use NVIDIA::Log;
use NVIDIA::Log::FileLogger;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Path qw(mkpath rmtree);

my $LogFile = basename($0) . '.log';
NVIDIA::Log::AddLogger(new NVIDIA::Log::FileLogger($LogFile));

my $NAME;
my $Subversion="3.3.3";
my $NeedCL; 
my $physx="3.3";
my @platforms = (
				'Windows',
				'OSX',
				'Android',
				'Linux')
				;
my $DownloadDir = $Bin;
my $mirror = 1;
my $multi  = 1;

GetOptions (
            "projectname=s"  => \$NAME,
            "subversion=s"   => \$Subversion,
			"cl=s"           => \$NeedCL,
			"physx=s"        => \$physx,
			"destination=s"  => \$DownloadDir,
			"mirror=i"       => \$mirror,
			"multi=i"        => \$multi,
			);

my @unusedFolders = (
			'externals\\cg',
			'Samples',
			);


system("git");

#unlink glob "$DownloadDir/*" if(-e $DownloadDir); 
#rmtree("$DownloadDir");

my $ProjectConfig;
my $project = "PhysXSDK-Installer-$physx-RELEASE-$Subversion";
my %BuildByPlatforms;
my $Builds;
  


#DeleteUnusedFile($DownloadDir);


my $PHYSX_GITHUB="https://github.com/gangzeng/myTest.git";

sub UploadToGitHub()
{   
    #system("C:\Users\gzeng.NVIDIA.COM\AppData\Local\GitHub\GitHub.appref-ms --open-shell");
}

UploadToGitHub();

sub GetPlatformsCL()
{
  foreach my $Platform (@platforms)
  {    
    my $projectCanName = "$project-$Platform";
	print "$projectCanName \n";
	my $Status = 'Unknown';
	my $Project = new NVIDIA::TeamCity::API::Project(
    { 'name' => $projectCanName}
	);
	
	$Project->LoadBuilds(top => 10);

	my $AllBuilds = $Project->{Builds};

	print Dumper ref($AllBuilds);
    
    my %CLs;
    foreach (sort {$b->BuildCL <=> $a->BuildCL} @$AllBuilds)
    {
      next unless ($_->BUILD_STATUS_OK eq $_->Status);
      my $CL = $_->BuildCL;
      next if ($CLs{$CL});
      
      $CLs{$CL} = 1;
      $BuildByPlatforms{$CL}->{$Platform} = $_;
      $BuildByPlatforms{$CL}->{Total} ++;
      
    }
  }
  
  foreach (sort {$BuildByPlatforms{$b}->{Total} <=> $BuildByPlatforms{$a}->{Total} 
                || $b <=> $a
                }
            keys %BuildByPlatforms )
  {
    return $_;
  }                
    
}
	
sub GetBuild
{
  my $ProjectCanName = shift;
  my $ProjectPlatform = shift;
  
  my $Status = 'Unknown';
  my $Project = new NVIDIA::TeamCity::API::Project(
    { 'name' => $ProjectCanName}
  );

  $Project->LoadBuilds(top => 10);

  my $Builds;
  my $AllBuilds = $Project->{Builds};
  foreach my $Build (@$AllBuilds)
  { 
    my $Changes = $Build->Changes();
    my $CL = Max($Changes);   #Cannot use $CL = Max($Build->Changes()) since Changes is dynamic loaded;
    
	if ($Build->{BuildCL} eq $NeedCL)
	{  
	   print "Current BuildCL:$Build->{BuildCL}, NeedCL:$NeedCL\n";
	   $Builds->{$ProjectPlatform}->{Build} = $Build if ($Build->{BuildCL} eq $NeedCL);
	   LogV(5, "Use your specified CL:$NeedCL, and the latest CL is $CL!");
	   last;
	}
	else
    {
        next;
    } 
  }
  
  if (!(defined $Builds->{$ProjectPlatform}->{Build}))
  {
    warn "Cannot find build for $ProjectPlatform\n";
  } else {
    my $Build = $Builds->{$ProjectPlatform}->{Build}; 
    $Status = $Build->Status(); #'BUILD FAILURE'
    if ($Status ne 'SUCCESS')
    {
      warn ">$ProjectPlatform found build: ". $Build->{Id}. " with status $Status, skip it\n";
      delete ($Builds->{$ProjectPlatform}); 
	  return $Builds;
    } else {
      $Builds->{$ProjectPlatform}->{ArtifactName} = $ProjectConfig->{$ProjectCanName}->{ARTIFACT_NAME};
	  $Builds->{$ProjectPlatform}->{SourceName} = $ProjectConfig->{$ProjectCanName}->{SOURCE_NAME};
	  print ">$ProjectPlatform found build: ". $Build->{Id}. "\n";
	  return $Builds;
    }
  }
}
sub DoDownload1
{
	my $Build = shift;
	my $dest   = shift;
   
	my $ArtifactName = shift;
	my $SourceName = shift;

	my $Platform = shift;
	
	print "** Downloading $Platform, ChangeList: $Build->{BuildCL}, BuildId: $Build->{Id}, Artifacts: $ArtifactName, SourceName: $SourceName\n";
	
	my $DownloadFile = ( $mirror eq '1' || $multi eq '1') ? $Build->DownloadMirrorArtifact($ArtifactName, $dest, "multi-threaded" => $multi):$Build->DownloadArtifact($ArtifactName, $dest);
	print "   Download complete!\n   Please check for $DownloadFile\n";
	ExtractFile ($DownloadFile, $dest);

	my $SourceFullName = "$dest/$NeedCL/$SourceName";
	ExtractFile ($SourceFullName, $dest);
	unlink ($dest . '/' . $ArtifactName);
}

sub DoDownload
{
   my $Builds = shift;
   my $dest   = shift;
   
   foreach my $Platform (keys %$Builds)
   {
     my $Build = $Builds->{$Platform}->{Build};
     my $ArtifactName = $Builds->{$Platform}->{ArtifactName};	 
     my $SourceName = $Builds->{$Platform}->{SourceName};	
	 print "** Downloading $Platform, ChangeList: $Build->{BuildCL}, BuildId: $Build->{Id}, Artifacts: $ArtifactName, SourceName: $SourceName\n";
	 my $DownloadFile = ( $mirror eq '1' || $multi eq '1') ? $Build->DownloadMirrorArtifact($ArtifactName, $dest, "multi-threaded" => $multi):$Build->DownloadArtifact($ArtifactName, $dest);
	 print "   Download complete!\n   Please check for $DownloadFile\n";
	 ExtractFile ($DownloadFile, $dest);

	 my $SourceFullName = "$dest/$NeedCL/$SourceName";
	 ExtractFile ($SourceFullName, $dest);
	 unlink ($dest . '/' . $ArtifactName);
   } 
}

sub DeleteUnusedFile()
{
	my $dest   = shift;
	my $deleTree = "$dest\\$NeedCL";
	rmtree ($deleTree)   if (-e $deleTree); 
	die "Cannot rmtree $deleTree" if (-e $deleTree);

	foreach my $unusedFolder (@unusedFolders)
	{
		$unusedFolder = $dest . $unusedFolder;
		if (-e $unusedFolder)
		{
			rmtree($unusedFolder)||die "Can not delete this dir!";print "$unusedFolder\n"
		}
	}
}

sub ExtractFile
{
   my $SourceFile = shift;
   my $DestDir = shift;
   
   my $zip = Archive::Zip->new($SourceFile);
   print "Extracting $SourceFile ....\n";
   foreach my $member ($zip->members)
    {
      next if $member->isDirectory;
      my $extractName = $member->fileName;
	  $member->extractToFileNamed("$DestDir/$extractName");
    }
	print "finished \n";
}

sub Max
{
  my $ArrRef = shift;

  my $Max = -1;
  foreach my $Item (@$ArrRef)
  {
    $Max = $Item if ($Max < $Item);
  }
  return $Max;
}
