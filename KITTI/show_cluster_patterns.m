function show_cluster_patterns(cid)

is_save = 0;

opt = globals;

% get image directory
root_dir = opt.path_kitti;
data_set = 'training';
cam = 2; % 2 = left color camera
image_dir = fullfile(root_dir, [data_set '/image_' sprintf('%02d', cam)]);

% load data
object = load('data_trainval.mat');
data = object.data;
idx = data.idx;

% load the mean CAD model
cls = 'car';
filename = sprintf('../Geometry/%s_mean.mat', cls);
object = load(filename);
cad_car = object.(cls);
index_car = cad_car.grid == 1;

% load pedestrian cad model
filename = '../Geometry/pedestrian.mat';
object = load(filename);
cad_pedestrian = object.pedestrian;
index_pedestrian = cad_pedestrian.grid == 1;

% load cyclist cad model
filename = '../Geometry/cyclist.mat';
object = load(filename);
cad_cyclist = object.cyclist;
index_cyclist = cad_cyclist.grid == 1;

% cluster centers
if nargin < 1
    centers = unique(idx);
    centers(centers == -1) = [];
else
    centers = cid;
end
N = numel(centers);

% azimuth = data.azimuth(centers);
% [~, ind] = sort(azimuth);
% centers = centers(ind);

% hf = figure('units','normalized','outerposition',[0 0 0.5 1]);
hf = figure;
nplot = 5;
mplot = 6;
for i = 1:N
    disp(i);
    ind = centers(i);

    bbox = data.bbox(:, idx == ind);
    % plot of center locations of bounding boxes
    x = (bbox(1,:) + bbox(3,:)) / 2;
    y = (bbox(2,:) + bbox(4,:)) / 2;

    h = subplot(nplot, mplot, 1:mplot/2);
    plot(x, y, 'o');
    set(h, 'Ydir', 'reverse');
    axis equal;
    axis([1 1242 1 375]);
    xlabel('x');
    ylabel('y');
    title('location');
    
    % plot of widths and heights of bounding boxes
    w = bbox(3,:) - bbox(1,:);
    h = bbox(4,:) - bbox(2,:);

    subplot(nplot, mplot, mplot/2+1:mplot);
    plot(w, h, 'o');
    axis equal;
    axis([1 1242 1 375]);
    xlabel('w');
    ylabel('h');
    title('width and height');    
    
    ind_plot = mplot + 1;
    % show center
    grid = data.grid{ind};
    type = data.type{ind};
    
    if strcmp(type, 'Car') || strcmp(type, 'Van')
        cad = cad_car;
        index = index_car;
    elseif strcmp(type, 'Pedestrian')
        cad = cad_pedestrian;
        index = index_pedestrian;
    elseif strcmp(type, 'Cyclist')
        cad = cad_cyclist;
        index = index_cyclist;
    end
    
    visibility_grid = zeros(size(cad.grid));
    visibility_grid(index) = grid;
    subplot(nplot, mplot, ind_plot);
    cla;
    ind_plot = ind_plot + 1;
    draw_cad(cad, visibility_grid);
    view(data.azimuth(ind), data.elevation(ind));
    
    % show the image patch
    seq_name = sprintf('%04d', data.sid(ind));
    filename = fullfile(image_dir, seq_name, data.imgname{ind});
    I = imread(filename);
    if data.is_flip(ind) == 1
        I = I(:, end:-1:1, :);
    end    
    bbox = data.bbox(:,ind);
    rect = [bbox(1) bbox(2) bbox(3)-bbox(1) bbox(4)-bbox(2)];
    I1 = imcrop(I, rect);
    subplot(nplot, mplot, ind_plot);
    ind_plot = ind_plot + 1;
    imshow(I1);
%     til = sprintf('w:%d, h:%d', size(I1,2), size(I1,1));
%     title(til);
    
    % show several members
    member = find(idx == ind);
    member(member == ind) = [];
    num = numel(member);
    fprintf('%d examples\n', num+1);
    for j = 1:min((nplot-1)*mplot/2-1, num)
        ind = member(j);
        grid = data.grid{ind};
        type = data.type{ind};
    
        if strcmp(type, 'Car') || strcmp(type, 'Van')
            cad = cad_car;
            index = index_car;
        elseif strcmp(type, 'Pedestrian')
            cad = cad_pedestrian;
            index = index_pedestrian;
        elseif strcmp(type, 'Cyclist')
            cad = cad_cyclist;
            index = index_cyclist;
        end       
        
        visibility_grid = zeros(size(cad.grid));
        visibility_grid(index) = grid;
        subplot(nplot, mplot, ind_plot);
        cla;
        ind_plot = ind_plot + 1;
        draw_cad(cad, visibility_grid);
        view(data.azimuth(ind), data.elevation(ind));
        
        % show the image patch
        seq_name = sprintf('%04d', data.sid(ind));        
        filename = fullfile(image_dir, seq_name, data.imgname{ind});
        I = imread(filename);
        if data.is_flip(ind) == 1
            I = I(:, end:-1:1, :);
        end        
        bbox = data.bbox(:,ind);
        rect = [bbox(1) bbox(2) bbox(3)-bbox(1) bbox(4)-bbox(2)];
        I1 = imcrop(I, rect);
        subplot(nplot, mplot, ind_plot);
        ind_plot = ind_plot + 1;
        imshow(I1);
%         til = sprintf('w:%d, h:%d', size(I1,2), size(I1,1));
%         title(til);        
    end
    for j = ind_plot:nplot*mplot
        subplot(nplot, mplot, j);
        cla;
        title('');
    end
    if is_save
        filename = sprintf('Clusters/%03d.png', i);
        saveas(hf, filename);
    else
        pause;
    end
end