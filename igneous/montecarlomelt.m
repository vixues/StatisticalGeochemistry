%% Load melt composition  data

%%%%%%%%%%%%%%%%%%%%%%% pMelts equil. batch melting %%%%%%%%%%%%%%%%%%%%%%%
H2O=0.15; % Initial Water
Pi=27000; % Initial Pressure
% Starting composition
sc = [44.8030; 0.1991; 4.4305; 0.9778; 0.3823; 7.1350; 0.1344; 37.6345; 0.2489; 0.0129; 3.5345; 0.3584; 0.0289; 0.0209; H2O;]; %mcdbse (McDonough Pyrolite)
% sc = [saltersdm.SiO2; saltersdm.TiO2; saltersdm.Al2O3; saltersdm.Fe2O3; saltersdm.Cr2O3; saltersdm.FeO; saltersdm.MnO; saltersdm.MgO; saltersdm.NiO; saltersdm.CoO; saltersdm.CaO; saltersdm.Na2O; saltersdm.K2O; saltersdm.P2O5; H2O;]; % Depleted Mantle
% Elements to include in simulation (must match starting composition)
elems={'SiO2';'TiO2';'Al2O3';'Fe2O3';'Cr2O3';'FeO';  'MnO';  'MgO';   'NiO';  'CoO';  'CaO';  'Na2O'; 'K2O'; 'P2O5'; 'H2O';};
% Batch string
batch='1\nsc.melts\n10\n1\n3\n1\nliquid\n1\n1.0\n0\n10\n0\n4\n0\n';
% Run simulation
melts=rmelts(sc,elems,'fo2path','FMQ','batchstring',batch,'mode','isobaric','dT',-10,'Ti',1700,'Tf',800,'Pi',Pi);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % Old method (deprecated)
% load melts20kbar
% meltdata=[melts20kbar.TiO2'; melts20kbar.Al2O3'; melts20kbar.Fe2O3t'; melts20kbar.MgO'; melts20kbar.CaO'; melts20kbar.Na2O'; melts20kbar.K2O']; 
% % Liquid_mass=melts20kbar.Liquid_mass;
% T=melts20kbar.T;

%% Load required variables
if ~exist('ign','var')
    load ign
end
ign.Age_Uncert=ign.Age_Max-ign.Age_Min;
ign.err.Age_Uncert=0;

% Simitems is a cell array holding the names of all the variables to
% examine. Names must be formatted as in ign.elements
simitemsin={'Age_Uncert';'Age';'SiO2';'TiO2';'Al2O3';'FeOT';'MgO';'CaO';'MnO';'Na2O';'K2O';};

% Elements in meltdata matrix must be in same order as simitemsin
meltdata=[melts.liquid_0.SiO2'; melts.liquid_0.TiO2'; melts.liquid_0.Al2O3'; melts.liquid_0.Fe2O3'./1.1113+melts.liquid_0.FeO'; melts.liquid_0.MgO'; melts.liquid_0.CaO'; melts.liquid_0.MnO'; melts.liquid_0.Na2O'; melts.liquid_0.K2O';]; 
% meltdata = meltdata./repmat((1.015-melts.liquid_0.H2O'/100),size(meltdata,1),1); %Nominally anhydrous normalization (doesn't noticeably change results) 
P = nanmean(melts.liquid_0.Pressure)/10000; %Pressure in GPa instead of bar
T=melts.liquid_0.Temperature;
Liquid_mass=melts.liquid_0.mass;

% Construct a matrix holding all the data to be used in the simulation
uncert=zeros(size(simitemsin))';
datain=zeros(length(ign.Age),length(simitemsin));
for i=1:length(simitemsin)
    datain(:,i)=ign.(simitemsin{i});
    uncert(i)=ign.err.(simitemsin{i});
end

%% Produce sample weights

% Range of silica values to examine
simin=43;
simax=54;
agemin=0;
agemax=4000;

% Reject data that is out of the range of interest, has NANs, or isn't from a contienent
test = ign.SiO2>simin &ign.SiO2<simax &ign.Age>agemin &ign.Age<agemax &sum(isnan(datain(:,3:end)),2)<2 &ign.Elevation>-100;
data=datain(test,:);

% Compute weighting coefficients
k=invweight(ign.Latitude(test),ign.Longitude(test),ign.Age(test));

% Compute probability keeping a given data point when sampling
prob=1./((k.*median(5./k))+1); % Keep rougly one-fith of the data in each resampling

% What to call the simulation results
simtitle=sprintf('%.2g-%.2g%% SiO_2',simin, simax);
printtitle=sprintf('si%g-%g',simin,simax);

%% Run the monte carlo simulation

tic;

% Number of simulations
nsims=10000;

% Number of variables to run the simulation for
ndata=3;

% Number of age divisions
nbins=40;

% Edges of age divisions
binedges=linspace(agemin,agemax,nbins+1)';

% Create 3-dimensional variables to hold the results
simaverages=zeros(nsims,nbins,ndata);
simerrors=zeros(nsims,nbins,ndata);
simratio=zeros(nsims,1);

% Compute age uncertainty for each sample
data(data(:,1)<10 | isnan(data(:,1)),1)=10;

% Run the simulation in parallel. Running the simulation task as a function
% avoids problems with indexing in parallelized code.
pool=gcp; %Start a parellel processing pool if there isn't one already
parfor i=1:nsims

    % mctask does all the hard work; simaverages and simerrors hold the results
    [simaverages(i,:,:), simerrors(i,:,:), simratio(i)]=mctaskmelt(data,prob,uncert,meltdata,Liquid_mass,T,P,binedges,nbins);
        
end
simerrors=simerrors.*(sqrt(nanmean(simratio))+1/sqrt(nsims));

toc % Record time taken to run simulation

% Compute vector of age-bin centers for plotting
bincenters=linspace(0+2000/nbins,4000-2000/nbins,nbins)';


% Simitems holds names for the outputs of mctask that are formatted to serve as figure titles
simitemsout={'Percent Melt';'Melting Temperature';'Potential Temperature'};
% Printnames contains quivalent names formatted as valid filenames
printnames={'percentmelt';'melttemp';'potentialtemp'};


%% Plot the results

% For each item in the simulation output, create a figure with the results
i=length(simitemsout);
while i>0
    figure
%     errorbar(bincenters,nanmean(simaverages(:,:,i)),2.*nanmean(simerrors(:,:,i)),'.r')
    plot(bincenters,nanmean(simaverages(:,:,i)),'k')
    xlabel('Age (Ma)')
    ylabel(simitemsout{i})
    title(simtitle)
    i=i-1;
end


%% Save results
mcmelt.bincenters=bincenters; mcmelt.simaverages=simaverages; mcmelt.simerrors=simerrors; mcmelt.simitems=simitemsout;
save(['mcmeltContinuous200ppm' num2str(round(P)) 'kign'],'mcmelt');


%% Plot the results from saved
% 
% % For each item in the simulation output, create a figure with the results
% i=length(simitemsout);
% while i>0
%     figure
%     errorbar(mcmelt.bincenters,nanmean(mcmelt.simaverages(:,:,i)),2.*nanmean(mcmelt.simerrors(:,:,i)),'.r')
%     xlabel('Age (Ma)')
%     ylabel(simitemsout{i})
%     i=i-1;
% end

%% Averages for various modern basalt types:
elems={'SiO2';'TiO2';'Al2O3';'FeOT';'MgO';'CaO';'MnO';'Na2O';'K2O';};
meltdata=[melts.liquid_0.SiO2'; melts.liquid_0.TiO2'; melts.liquid_0.Al2O3'; melts.liquid_0.Fe2O3'./1.1113+melts.liquid_0.FeO'; melts.liquid_0.MgO'; melts.liquid_0.CaO'; melts.liquid_0.MnO'; melts.liquid_0.Na2O'; melts.liquid_0.K2O';]; 
T=melts.liquid_0.Temperature;
Liquid_mass=melts.liquid_0.mass;
P = nanmean(melts.liquid_0.Pressure)/10000; %Pressure in GPa instead of bar
if ~exist('ign','var'); load ign; end
if ~exist('mcign','var'); load mcign; end
if ~isfield(mcign,'Geolprov'); mcign.Geolprov = findgeolprov(mcign.Latitude,mcign.Longitude); end

test = mcign.SiO2>43 & mcign.SiO2<51;
% test = test & mcign.Geolprov == 11; fprintf('Island arc:\n'); %% Island arc
% test = test & mcign.Geolprov == 12; fprintf('Continental arc:\n'); %% Continental arc
test = test & mcign.Geolprov == 21; fprintf('Continental rift:\n');%% Rift
% test = test & mcign.Geolprov == 22; fprintf('Continental flood basalt:\n');%% Flood basalt
composition=zeros(length(elems), sum(test));
for i=1:length(elems)
    composition(i,:)=mcign.(elems{i})(test);
end
composition = composition(:,sum(isnan(composition),1)<2);

% Find best-fitting melt percentages
index=zeros(size(composition,2),1);
for i=1:size(composition,2)
    a=repmat(composition(:,i),1,size(meltdata,2));
    [~, index(i)]=min(nansum(((a-meltdata)./a).^2,1));
end

PercentMelt=Liquid_mass(index); %Meltestimate
MeltingTemp=T(index); %Tempestimate
PotentialTemp=potentialtemperature(T(index)+273.15,P)-273.15; %Mantle potential tempestimate

fprintf('Percent Melt: %g +/- %g +/- %g\n', nanmean(PercentMelt), nansem(PercentMelt)*sqrt(length(mcign.SiO2)/length(ign.SiO2)), nanmad(PercentMelt));
fprintf('Potential Temperature: %g +/- %g +/- %g\n', nanmean(PotentialTemp), nansem(PotentialTemp)*sqrt(length(mcign.SiO2)/length(ign.SiO2)), nanmad(PotentialTemp));

%% OIB
elems={'SiO2';'TiO2';'Al2O3';'FeOT';'MgO';'CaO';'MnO';'Na2O';'K2O';};
meltdata=[melts.liquid_0.SiO2'; melts.liquid_0.TiO2'; melts.liquid_0.Al2O3'; melts.liquid_0.Fe2O3'./1.1113+melts.liquid_0.FeO'; melts.liquid_0.MgO'; melts.liquid_0.CaO'; melts.liquid_0.MnO'; melts.liquid_0.Na2O'; melts.liquid_0.K2O';]; 
T=melts.liquid_0.Temperature;
Liquid_mass=melts.liquid_0.mass;
P = nanmean(melts.liquid_0.Pressure)/10000; %Pressure in GPa instead of bar

test = ign.SiO2>43 & ign.SiO2<51;
test = test & ign.oibs;
composition=zeros(length(elems), sum(test));
for i=1:length(elems)
    composition(i,:)=ign.(elems{i})(test);
end
composition = composition(:,sum(isnan(composition),1)<2);

% Find best-fitting melt percentages
index=zeros(size(composition,2),1);
for i=1:size(composition,2)
    a=repmat(composition(:,i),1,size(meltdata,2));
    [~, index(i)]=min(nansum(((a-meltdata)./a).^2,1));
end

PercentMelt=Liquid_mass(index); %Meltestimate
MeltingTemp=T(index); %Tempestimate
PotentialTemp=potentialtemperature(T(index)+273.15,P)-273.15; %Mantle potential tempestimate

fprintf('OIB:\n');
fprintf('Percent Melt: %g +/- %g +/- %g\n', nanmean(PercentMelt), nansem(PercentMelt), nanmad(PercentMelt));
fprintf('Potential Temperature: %g +/- %g +/- %g\n', nanmean(PotentialTemp), nansem(PotentialTemp), nanmad(PotentialTemp));

%% MORB
if ~exist('morb','var'); load morb; end
if ~exist('mcmorb','var'); load mcmorb; end

elems={'SiO2';'TiO2';'Al2O3';'FeOT';'MgO';'CaO';'MnO';'Na2O';'K2O';};
meltdata=[melts.liquid_0.SiO2'; melts.liquid_0.TiO2'; melts.liquid_0.Al2O3'; melts.liquid_0.Fe2O3'./1.1113+melts.liquid_0.FeO'; melts.liquid_0.MgO'; melts.liquid_0.CaO'; melts.liquid_0.MnO'; melts.liquid_0.Na2O'; melts.liquid_0.K2O';]; 
T=melts.liquid_0.Temperature;
Liquid_mass=melts.liquid_0.mass;
P = nanmean(melts.liquid_0.Pressure)/10000; %Pressure in GPa instead of bar

test = mcmorb.SiO2>43 & mcmorb.SiO2<51;
composition=zeros(length(elems), sum(test));
for i=1:length(elems)
    composition(i,:)=mcmorb.(elems{i})(test);
end
composition = composition(:,sum(isnan(composition),1)<2);

% Find best-fitting melt percentages
index=zeros(size(composition,2),1);
for i=1:size(composition,2)
    a=repmat(composition(:,i),1,size(meltdata,2));
    [~, index(i)]=min(nansum(((a-meltdata)./a).^2,1));
end

PercentMelt=Liquid_mass(index); %Meltestimate
MeltingTemp=T(index); %Tempestimate
PotentialTemp=potentialtemperature(T(index)+273.15,P)-273.15; %Mantle potential tempestimate

fprintf('MORB:\n');
fprintf('Percent Melt: %g +/- %g +/- %g\n', nanmean(PercentMelt), nansem(PercentMelt)*sqrt(length(mcmorb.SiO2)/length(morb.SiO2)), nanmad(PercentMelt));
fprintf('Potential Temperature: %g +/- %g +/- %g\n', nanmean(PotentialTemp), nansem(PotentialTemp)*sqrt(length(mcmorb.SiO2)/length(morb.SiO2)), nanmad(PotentialTemp));
