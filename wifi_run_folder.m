function folder = wifi_run_folder(parent,label)
%WIFI_RUN_FOLDER Reserve a timestamped output directory without overwriting.
if nargin<2, label='run'; end
validateattributes(parent,{'char'},{'row','nonempty'});
label=regexprep(label,'[^a-zA-Z0-9_-]','_');
if ~exist(parent,'dir'), [ok,msg]=mkdir(parent); assert(ok,'%s',msg); end
stem=[label '_' datestr(now,'yyyymmdd_HHMMSS_FFF')];
for k=0:9999
    name=stem; if k>0, name=sprintf('%s_%03d',stem,k); end
    folder=fullfile(parent,name);
    if exist(folder,'dir'), continue; end
    [ok,msg,id]=mkdir(folder);
    assert(ok,'%s',msg);
    if ~strcmp(id,'MATLAB:MKDIR:DirectoryExists')
        [resolved,attributes]=fileattrib(folder);
        if resolved, folder=attributes.Name; end
        return
    end
end
error('Could not reserve a unique run folder.');
end
