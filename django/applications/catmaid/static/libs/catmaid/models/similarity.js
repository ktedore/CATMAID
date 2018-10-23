/* -*- mode: espresso; espresso-indent-level: 2; indent-tabs-mode: nil -*- */
/* vim: set softtabstop=2 shiftwidth=2 tabstop=2 expandtab: */

(function(CATMAID) {

  "use strict";

  var Similarity = {};

  /**
   * Test if the NBLAST environment is set up.
   */
  Similarity.testEnvironment = function(projectId) {
    return CATMAID.fetch(projectId + '/similarity/test-setup');
  };

  /**
   * Get a list of all similarity configurations in this project.
   *
   * @param projectId {integer} The project to operate in.
   *
   * @returns a promise that resolves in the list of configurations.
   */
  Similarity.listAllConfigs = function(projectId, simple) {
    return CATMAID.fetch(projectId + '/similarity/configs/', 'GET', {
      simple: !!simple
    });
  };

  /**
   * Get details on a particular similarity configuration.
   */
  Similarity.getConfig = function(projectId, configId) {
    return CATMAID.fetch(projectId + '/similarity/configs/' + configId + '/');
  };

  /**
   * Delete a similarity configuration.
   */
  Similarity.deleteConfig = function(projectId, configId) {
    return CATMAID.fetch(projectId + '/similarity/configs/' + configId + '/',
        'DELETE')
      .then(function(result) {
        CATMAID.Similarity.trigger(CATMAID.Similarity.EVENT_CONFIG_DELETED, configId);
        return result;
      });
  };

  /**
   * Add a new similarity configuration.
   */
  Similarity.addConfig = function(projectId, name, matchingSkeletonIds,
      randomSkeletonIds, numRandomNeurons, lengthRandomNeurons, distanceBreaks,
      dotBreaks, tangentNeighbors) {
    if (!matchingSkeletonIds || matchingSkeletonIds.length === 0) {
      return Promise.reject(new CATMAID.Warning("No matching set skeleton IDs found"));
    }
    if (!randomSkeletonIds) {
      return Promise.reject(new CATMAID.Warning("No random set skeleton IDs found"));
    }

    let params = {
      name: name,
      matching_skeleton_ids: matchingSkeletonIds,
      random_skeleton_ids: randomSkeletonIds,
      distance_breaks: distanceBreaks,
      dot_breaks: dotBreaks,
      tangent_neighbors: tangentNeighbors,
    };
    if (randomSkeletonIds === 'backend') {
      params.n_random_skeletons = numRandomNeurons;
      params.min_length = lengthRandomNeurons;
    }

    return CATMAID.fetch(project.id + '/similarity/configs/', 'PUT', params)
      .then(function(result) {
        CATMAID.Similarity.trigger(CATMAID.Similarity.EVENT_CONFIG_ADDED, result);
        return result;
      });
  };

  /**
   * Queue recomputation of a similarity configuration.
   */
  Similarity.recomputeConfig = function(projectId, configId) {
    return CATMAID.fetch(projectId + '/similarity/configs/' + configId + '/recompute');
  };

  /**
   * Compute similarity between two sets of skeletons based on a particular
   * configuration.
   *
   * @param projectId  {Number}   The project to operate in.
   * @param configId   {Number}   NBLAST configuration to use.
   * @param queryIds   {Number[]} A list of query skeletons to compute
   *                              similarity for.
   * @param targetIds  {Number[]} A list of target object IDs to compare to,
   *                              can be skeleton IDs and point cloud IDs.
   * @param queryType  {String}   (optional) Type of query IDs, 'skeleton' or 'pointcloud'.
   * @param targetType {String}   (optional) Type of target IDs, 'skeleton' or 'pointcloud'.
   * @param name       {String}   The name of the query.
   * @param queryMeta  {Object}   (optional) Data that represents query objects in more detail.
   *                              Used with type 'transformed-skeleton' and maps skeleton IDs
   *                              to their transformed data.
   * @param targetMeta {Object}   (optional) Data that represents target objects in more detail.
   *                              Used with type 'transformed-skeleton' and maps skeleton IDs
   *                              to their transformed data.
   *
   * @returns {Promise} Resolves once the similarity query is queued.
   */
  Similarity.computeSimilarity = function(projectId, configId, queryIds,
      targetIds, queryType, targetType, name, queryMeta, targetMeta) {
    return CATMAID.fetch(projectId + '/similarity/queries/similarity', 'POST', {
      'query_ids': queryIds,
      'target_ids': targetIds,
      'query_type_id': queryType,
      'target_type_id': targetType,
      'config_id': configId,
      'query_meta': queryMeta,
      'target_meta': targetMeta,
      'name': name,
    });
  };

  /**
   * Queue recomputation of a similarity configuration.
   */
  Similarity.recomputeSimilarity = function(projectId, similarityId) {
    return CATMAID.fetch(projectId + '/similarity/queries/' + similarityId + '/recompute');
  };

  /**
   * Get a specific similarity query result.
   */
  Similarity.getSimilarity = function(projectId, similarityId) {
    return CATMAID.fetch(projectId + '/similarity/queries/' + similarityId + '/');
  };

  /**
   * Get a list of all similarity tasks in this project.
   *
   * @param projectId {integer} The project to operate in.
   * @param configId  {integer} (optional) ID of config the similarities are linked to.
   *
   * @returns a promise that resolves in the list of similarities.
   */
  Similarity.listAllSkeletonSimilarities = function(projectId, configId) {
    return CATMAID.fetch(projectId + '/similarity/queries/', 'GET', {
      configId: configId
    });
  };

  /**
   * Delete a particular skeleton similarity task.
   */
  Similarity.deleteSimilarity = function(projectId, similarityId) {
    return CATMAID.fetch(projectId + '/similarity/queries/' + similarityId + '/',
        'DELETE')
      .then(function(result) {
        CATMAID.Similarity.trigger(CATMAID.Similarity.EVENT_SIMILARITY_DELETED, similarityId);
        return result;
      });
  };

  Similarity.getReferencedSkeletonModels = function(similarity) {
    let targetModels = {};
    if (similarity.target_type === 'skeleton') {
      similarity.target_objects.reduce(function(o, to) {
        o[to] = new CATMAID.SkeletonModel(to);
        return o;
      }, targetModels);
    }
    if (similarity.query_type === 'skeleton') {
      similarity.query_objects.reduce(function(o, to) {
        o[to] = new CATMAID.SkeletonModel(to);
        return o;
      }, targetModels);
    }
    return targetModels;
  };

  Similarity.defaultDistanceBreaks = [0, 0.75, 1.5, 2, 2.5, 3, 3.5, 4, 5, 6, 7,
      8, 9, 10, 12, 14, 16, 20, 25, 30, 40, 500];
  Similarity.defaultDotBreaks = [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1];


  // Events
  Similarity.EVENT_CONFIG_ADDED = "similarity_config_added";
  Similarity.EVENT_CONFIG_DELETED = "similarity_config_deleted";
  CATMAID.asEventSource(Similarity);


  // Export into namespace
  CATMAID.Similarity = Similarity;

})(CATMAID);
