% create annotations with occlusion masks for KITTI dataset
function create_annotations

matlabpool open;

opt = globals();
pad_size = 1000;

% load car cad models
cls = 'car';
filename = sprintf('../Geometry/%s.mat', cls);
object = load(filename);
cads = object.(cls);

% load mean model
filename = sprintf('../Geometry/%s_mean.mat', cls);
object = load(filename);
cad_mean = object.(cls);

% load pedestrian cad model
filename = '../Geometry/pedestrian.mat';
object = load(filename);
cad_pedestrian = object.pedestrian;

% load cyclist cad model
filename = '../Geometry/cyclist.mat';
object = load(filename);
cad_cyclist = object.cyclist;

% kitti path
root_dir = opt.path_kitti;
data_set = 'training';

% get sub-directories
cam = 2; % 2 = left color camera
image_dir = fullfile(root_dir, [data_set '/image_' sprintf('%02d', cam)]);
label_dir = fullfile(root_dir, [data_set '/label_' sprintf('%02d', cam)]);
calib_dir = fullfile(root_dir, [data_set '/calib']);

num_seqs = numel(opt.kitti_train_seqs);
for k = 1:num_seqs

    % get number of images for this dataset
    seq_name = opt.kitti_train_seqs{k};
    seq_idx = str2double(seq_name);
    nimages = opt.kitti_train_nums(k);
    
    % load projection matrix
    P = readCalibration(calib_dir, seq_idx, cam);
    
    % load labels
    tracklets = readLabels(label_dir, seq_idx);

    % main loop
    parfor img_idx = 0:nimages-1        
      record = [];
      record.folder = data_set;
      record.seq_name = seq_name;
      record.filename = sprintf('%06d.png', img_idx);

      % read image
      I = imread(sprintf('%s/%s/%06d.png',image_dir, seq_name, img_idx));
      [h, w, d] = size(I);

      record.size.width = w;
      record.size.height = h;
      record.size.depth = d;
      record.imgsize = [w h d];

      mask = zeros(h, w);
      mask = padarray(mask, [pad_size pad_size]);

      % projection matrix
      record.projection = P;

      % objects in this frame
      objects = tracklets{img_idx + 1};

      % sort objects from large distance to small distance
      index = sort_objects(objects);

      % for all annotated objects do
      num = numel(index);
      BWs = cell(num, 1);
      for i = 1:num
        obj_idx = index(i);
        % plot 2D bounding box
        object = objects(obj_idx);

        if strcmp(object.type, 'Car') == 1 || strcmp(object.type, 'Van') == 1
            cad_index = find_closest_cad(cads, object);
            x3d = compute_3d_points(cads(cad_index).vertices, object);
            face = cads(cad_index).faces;
            objects(obj_idx).cad_index = cad_index;
        elseif strcmp(object.type, 'Pedestrian') == 1
            x3d = compute_3d_points(cad_pedestrian.vertices, object);
            face = cad_pedestrian.faces;
            objects(obj_idx).cad_index = 1;
        elseif strcmp(object.type, 'Cyclist') == 1
            x3d = compute_3d_points(cad_cyclist.vertices, object);
            face = cad_cyclist.faces;
            objects(obj_idx).cad_index = 1;
        else
            x3d = [];
        end

        if isempty(x3d) == 0
            x2d = projectToImage(x3d, P);    
            x2d = x2d';

            flag = max(x2d(:,1)) - min(x2d(:,1)) > w;
            if flag == 1
                continue;
            end

            x2d = x2d + pad_size;
            vertices = [x2d(face(:,1),2) x2d(face(:,1),1) ...
                        x2d(face(:,2),2) x2d(face(:,2),1) ...
                        x2d(face(:,3),2) x2d(face(:,3),1)];

            BWs{obj_idx} = mesh_test(vertices, h+2*pad_size, w+2*pad_size);

            mask(BWs{obj_idx}) = obj_idx;
        end

      end
      mask = mask(pad_size+1:h+pad_size, pad_size+1:w+pad_size);
      mask = padarray(mask, [pad_size pad_size], -1);
      record.pad_size = pad_size;
      record.mask = mask;

      % create occlusion patterns
      index_object = index;
      for i = 1:num
          azimuth = objects(i).alpha*180/pi;
          if azimuth < 0
              azimuth = azimuth + 360;
          end
          azimuth = azimuth - 90;
          if azimuth < 0
              azimuth = azimuth + 360;
          end
          distance = norm(objects(i).t);
          elevation = asind(objects(i).t(2)/distance);
          objects(i).azimuth = azimuth;
          objects(i).elevation = elevation;
          objects(i).distance = distance;
          objects(i).is_flip = 0;

          if isempty(BWs{i}) == 1
              objects(i).pattern = [];
              objects(i).occ_per = 0;
              objects(i).trunc_per = 0;
              objects(i).grid = [];
              objects(i).grid_origin = [];
              continue;
          end

          pattern = uint8(BWs{i});  % 1 visible
          pattern(mask > 0 & mask ~= i & BWs{i}) = 2;  % occluded
          pattern(mask == -1 & BWs{i}) = 3;  % truncated
          [x, y] = find(pattern > 0);
          pattern = pattern(min(x):max(x), min(y):max(y));
          objects(i).pattern = pattern;

          % compute occlusion percentage
          occ = numel(find(pattern == 2)) / numel(find(pattern > 0));
          objects(i).occ_per = occ;

          % compute truncation percentage
          trunc = numel(find(pattern == 3)) / numel(find(pattern > 0));
          objects(i).trunc_per = trunc;

          % 3D occlusion mask for mean shape
          if strcmp(objects(i).type, 'Car') == 1 || strcmp(objects(i).type, 'Van') == 1
              cad_mean_model = cad_mean;
          elseif strcmp(objects(i).type, 'Pedestrian') == 1
              cad_mean_model = cad_pedestrian;
          elseif strcmp(objects(i).type, 'Cyclist') == 1
              cad_mean_model = cad_cyclist;
          end      
          [visibility_grid, visibility_ind] = check_visibility(cad_mean_model, azimuth, elevation);

          % check the occlusion status of visible voxels
          index = find(visibility_ind == 1);
          x3d = compute_3d_points(cad_mean_model.x3d(index,:), objects(i));
          x2d = projectToImage(x3d, P);
          x2d = x2d' + pad_size;
          occludee = find(index_object == i);
          for j = 1:numel(index)
              x = round(x2d(j,1));
              y = round(x2d(j,2));
              ind = cad_mean_model.ind(index(j),:);
              if x > pad_size && x <= size(mask,2)-pad_size && y > pad_size && y <= size(mask,1)-pad_size
                  if mask(y,x) > 0 && mask(y,x) ~= i % occluded by other objects
                      occluder = find(index_object == mask(y,x));
                      if occluder > occludee
                        visibility_grid(ind(1), ind(2), ind(3)) = 2;
                      end
                  end
              else
                  visibility_grid(ind(1), ind(2), ind(3)) = 3;  % truncated
              end
          end
          objects(i).grid = visibility_grid;

          % 3D occlusion mask for original shape
          if strcmp(objects(i).type, 'Car') == 1 || strcmp(objects(i).type, 'Van') == 1
              cad_index = objects(i).cad_index;
              cad = cads(cad_index);
          elseif strcmp(objects(i).type, 'Pedestrian') == 1
              cad = cad_pedestrian;
          elseif strcmp(objects(i).type, 'Cyclist') == 1
              cad = cad_cyclist;          
          end
          [visibility_grid, visibility_ind] = check_visibility(cad, azimuth, elevation);

          % check the occlusion status of visible voxels
          index = find(visibility_ind == 1);
          x3d = compute_3d_points(cad.x3d(index,:), objects(i));
          x2d = projectToImage(x3d, P);
          x2d = x2d' + pad_size;
          occludee = find(index_object == i);
          for j = 1:numel(index)
              x = round(x2d(j,1));
              y = round(x2d(j,2));
              ind = cad.ind(index(j),:);
              if x > pad_size && x <= size(mask,2)-pad_size && y > pad_size && y <= size(mask,1)-pad_size
                  if mask(y,x) > 0 && mask(y,x) ~= i % occluded by other objects
                      occluder = find(index_object == mask(y,x));
                      if occluder > occludee
                        visibility_grid(ind(1), ind(2), ind(3)) = 2;
                      end
                  end
              else
                  visibility_grid(ind(1), ind(2), ind(3)) = 3;  % truncated
              end
          end
          objects(i).grid_origin = visibility_grid;      
      end
      record.objects = objects;

      % flip the mask
      mask_flip = mask(:,end:-1:1);
      record.mask_flip = mask_flip;

      % add flipped objects
      objects_flip = objects;
      for i = 1:num
          objects_flip(i).is_flip = 1;
          % flip bbox
          oldx1 = objects(i).x1;
          oldx2 = objects(i).x2;        
          objects_flip(i).x1 = w - oldx2 + 1;
          objects_flip(i).x2 = w - oldx1 + 1;        

          % flip viewpoint
          azimuth = objects(i).azimuth;
          azimuth = 360 - azimuth;
          if azimuth >= 360
              azimuth = 360 - azimuth;
          end
          objects_flip(i).azimuth = azimuth;
          alpha = azimuth + 90;
          if alpha >= 360
              alpha = alpha - 360;
          end
          alpha = alpha*pi/180;
          if alpha > pi
              alpha = alpha - 2*pi;
          end
          objects_flip(i).alpha = alpha;
          elevation = objects(i).elevation;

          % find the 3d location of the flipped object

          % use the object center instead of bounding box center
          x3d = compute_3d_points_noscaling([0 0 0], objects(i));
          x2d = projectToImage(x3d, P);
          x2d(1) = w - x2d(1) + 1;
          c = [x2d; 1];

          % backprojection
          X = pinv(P) * c;
          X = X ./ X(4);
          if X(3) < 0
              X = -1 * X;
          end
          X(4) = [];
          X = X ./ norm(X);  
          objects_flip(i).ry = objects_flip(i).alpha + atan(X(1)/X(3));
          objects_flip(i).t = norm(objects(i).t) .* X';
          objects_flip(i).t(2) = objects_flip(i).t(2) + objects(i).h/2;

          if isempty(objects(i).grid) == 1
              continue;
          end          

          % flip pattern
          pattern = objects(i).pattern;
          objects_flip(i).pattern = pattern(:,end:-1:1);

          % 3D occlusion mask for mean shape
          if strcmp(objects(i).type, 'Car') == 1 || strcmp(objects(i).type, 'Van') == 1
              cad_mean_model = cad_mean;
          elseif strcmp(objects(i).type, 'Pedestrian') == 1
              cad_mean_model = cad_pedestrian;
          elseif strcmp(objects(i).type, 'Cyclist') == 1
              cad_mean_model = cad_cyclist;
          end           
          [visibility_grid, visibility_ind] = check_visibility(cad_mean_model, azimuth, elevation);

          % check the occlusion status of visible voxels
          index = find(visibility_ind == 1);
          x3d = compute_3d_points(cad_mean_model.x3d(index,:), objects_flip(i));
          x2d = projectToImage(x3d, P);
          x2d = x2d' + pad_size;
          occludee = find(index_object == i);
          for j = 1:numel(index)
              x = round(x2d(j,1));
              y = round(x2d(j,2));
              ind = cad_mean_model.ind(index(j),:);
              if x > pad_size && x <= size(mask_flip,2)-pad_size && y > pad_size && y <= size(mask_flip,1)-pad_size
                  if mask_flip(y,x) > 0 && mask_flip(y,x) ~= i % occluded by other objects
                      occluder = find(index_object == mask_flip(y,x));
                      if occluder > occludee
                        visibility_grid(ind(1), ind(2), ind(3)) = 2;
                      end
                  end
              else
                  visibility_grid(ind(1), ind(2), ind(3)) = 3;  % truncated
              end
          end
          objects_flip(i).grid = visibility_grid;

          % 3D occlusion mask for original shape
          if strcmp(objects(i).type, 'Car') == 1 || strcmp(objects(i).type, 'Van') == 1
              cad_index = objects_flip(i).cad_index;
              cad = cads(cad_index);
          elseif strcmp(objects(i).type, 'Pedestrian') == 1
              cad = cad_pedestrian;
          elseif strcmp(objects(i).type, 'Cyclist') == 1
              cad = cad_cyclist;          
          end
          [visibility_grid, visibility_ind] = check_visibility(cad, azimuth, elevation);

          % check the occlusion status of visible voxels
          index = find(visibility_ind == 1);
          x3d = compute_3d_points(cad.x3d(index,:), objects_flip(i));
          x2d = projectToImage(x3d, P);     
          x2d = x2d' + pad_size;
          occludee = find(index_object == i);
          for j = 1:numel(index)
              x = round(x2d(j,1));
              y = round(x2d(j,2));
              ind = cad.ind(index(j),:);
              if x > pad_size && x <= size(mask_flip,2)-pad_size && y > pad_size && y <= size(mask_flip,1)-pad_size
                  if mask_flip(y,x) > 0 && mask_flip(y,x) ~= i % occluded by other objects
                      occluder = find(index_object == mask_flip(y,x));
                      if occluder > occludee
                        visibility_grid(ind(1), ind(2), ind(3)) = 2;
                      end
                  end
              else
                  visibility_grid(ind(1), ind(2), ind(3)) = 3;  % truncated
              end
          end
          objects_flip(i).grid_origin = visibility_grid;
      end  

      % save annotation
      record.objects_flip = objects_flip;
      if exist(fullfile('Annotations', seq_name), 'dir') == 0
          mkdir(fullfile('Annotations', seq_name));
      end
      filename = sprintf('Annotations/%s/%06d.mat', seq_name, img_idx);
      disp(filename);
      parsave(filename, record);
    end
end

matlabpool close;

function parsave(fname, record)
save(fname, 'record')