-- This function will drop a table with the given name and recreates it as
-- an intersection table. i.e. with the fields id, child_id, parent_id,
-- intersection.
CREATE OR REPLACE FUNCTION recreate_intersection_table(table_name text)
RETURNS void AS $$
DECLARE
  seq_name text;
  tmp_name text;
  row_count integer;
BEGIN
  -- We need to store the table name in a separate variable, because a regclass
  -- type variable will be invalid after the table is removed that it refers to.
  tmp_name = '' || table_name;

  -- Test if table exists
  EXECUTE format($a$SELECT COUNT(*) FROM pg_class WHERE relname='%s'$a$, table_name)
    INTO row_count;

  IF row_count <> 0
  THEN
    EXECUTE format('DROP TABLE %s', table_name);
  END IF;

  -- Prepare sequence name
  seq_name = format('%s_id_seq', tmp_name);

  -- Create intersection table
  EXECUTE format('CREATE TABLE %I (
    id bigint PRIMARY KEY,
    child_id bigint NOT NULL,
    parent_id bigint,
    intersection double3d NOT NULL,
    CONSTRAINT ' || tmp_name || '_child_id_fkey FOREIGN KEY (child_id)
        REFERENCES treenode(id),
    CONSTRAINT ' || tmp_name || '_parent_id_fkey FOREIGN KEY (parent_id)
        REFERENCES treenode(id))', tmp_name);
  EXECUTE format('CREATE SEQUENCE %s START WITH 1 INCREMENT BY 1 ' ||
    'NO MINVALUE NO MAXVALUE CACHE 1', seq_name);
  EXECUTE format('ALTER SEQUENCE %s OWNED BY %s.id', seq_name, tmp_name);
  EXECUTE format('ALTER TABLE ONLY %s ALTER COLUMN id ' ||
    $a$SET DEFAULT nextval('%s'::regclass)$a$, tmp_name, seq_name);

  RETURN;
END;
$$ LANGUAGE plpgsql;

-- This function shrinks the treenode table by removing all treenodes that are
-- on a straight line between its neighbors and are no branch points and are not
-- referened in any other way (e.g. by tags).
CREATE OR REPLACE FUNCTION reduce_treenode_table()
RETURNS void AS $$
BEGIN
  RETURN;
END;
$$ LANGUAGE plpgsql;


-- This function populates an intersection table for a specific stack. It
-- will create an intersection for every edge in the treenode table. Two
-- parameters are required: project ID and stack ID.
-- This function walks all skeltons in the treenode table and finds
-- intersections between sekeltons and slices for a given stack. Next to project
-- and stack ID, it expects the target table to be passed as a parameter. The
-- target table has to exist already. This function doesn't remove data from the
-- target table, but only adds to it.
--
-- TODO: What to do with broken slices?
CREATE OR REPLACE FUNCTION populate_intersection_table(integer, integer, table_name reglass)
RETURNS integer AS $$
DECLARE
  stack_id ALIAS FOR $1;
  pid ALIAS FOR $2;
  table_name ALIAS FOR $3;
  dimension stack.dimension%TYPE;
  resolution stack.resolution%TYPE;
  loc treenode.location%TYPE;
  skeleton_class_id integer;
  root_node_id integer;
  skeleton class_instance%ROWTYPE;
  node RECORD;
  section_distance double precision;
  num_intersections integer;
  num_treenodes integer;
  treenode_count integer;
  insert_statement text;
  -- edge_count integer;
BEGIN
  -- Get the stack's dimension and resolution
  SELECT (s.dimension).* INTO dimension FROM stack s WHERE id = stack_id LIMIT 1;
  SELECT (s.resolution).* INTO resolution FROM stack s WHERE id = stack_id LIMIT 1;
  -- Make sure we got the data we want
  IF NOT FOUND THEN
      RAISE EXCEPTION 'stack % not found', stack_id;
  END IF;

  -- Get ID of 'skeleton' class
  SELECT id INTO skeleton_class_id FROM class WHERE class_name = 'skeleton' LIMIT 1;

  -- Find out how many treenodes we have
  SELECT count(*) INTO num_treenodes FROM treenode;
  treenode_count = 0;


  -- Prepare basic insert statement
  insert_statement = format('INSERT INTO %s (child_id, parent_id, intersection) ' ||
    'VALUES ($1, $2, $3)', table_name);

  -- Walk each skeleton of this project from root to all leafes. This is faster
  -- than walking sequencially though a big join. Expect the skeleton to have no
  -- loops.
  FOR skeleton IN SELECT * FROM class_instance ci WHERE ci.project_id = pid
      AND ci.class_id = skeleton_class_id LOOP

    -- Build a Common Table Expression to build up the skeleton tree with all
    -- location information needed and traverse it.
    FOR node IN
        WITH RECURSIVE skeleton_tree(id, location, parent_id, parent_location) AS (
            -- Non-recursive part: the root node, expect only one per skeleton. The
            -- NULL value for the (non existing) parent location has to be typed or
            -- Postgres will default to TEXT type and complain.
            SELECT id, location, parent_id, location
                FROM treenode WHERE skeleton_id = skeleton.id AND parent_id IS NULL
          UNION ALL
            -- Recursive part which can reference the query's own output
            SELECT t.id, t.location, s.id, s.location
                FROM treenode t, skeleton_tree s WHERE s.id = t.parent_id
        )
        SELECT * FROM skeleton_tree
    LOOP
      -- Output status information
      treenode_count = treenode_count + 1;
      RAISE NOTICE 'Status: %/%', treenode_count, num_treenodes;

      -- In every iteration one node of the current skeleton as 'node'. It has
      -- the properties 'id', 'location', 'parent_id' and 'parent_location'. The
      -- last two are NULL for the root node. Based on this, all intersections
      -- can be calculated. Start with the current location and add an
      -- intersection, if it is on a section.
      section_distance = MOD((node.location).z::numeric, resolution.z::numeric);
      IF section_distance < 0.0001 THEN
          -- RAISE NOTICE 'Skeleton %: adding intersection: %', skeleton.id, node.location;
          EXECUTE insert_statement USING node.id, node.parent_id, node.location;
      END IF;

      -- Calculate the number of extra intersections. Substract one to
      -- compensate for the intersection that has been potentially added above.
      num_intersections = abs((node.location).z - (node.parent_location).z) / resolution.z - 1;

      -- Continue with next node if there are -1 or zero intersections. Minus
      -- one will happen for the root node and zero if the parent node is on the
      -- next slice. Display intersections with:
      -- RAISE NOTICE '# Intersections: %', num_intersections;
      IF num_intersections > 0 THEN
        CONTINUE;
      END IF;

      -- Calculate the vector in direction of the next intersection
      
      -- If the parent node's Z is lower than the current node's Z, check
      -- backwars for intersections. Otherwise go forwards.
      IF (node.parent_location).z < (node.location).z THEN
        -- Go to the next intersection before this slice
        WHILE num_intersections > 0 LOOP
          RAISE NOTICE '  Adding addition intersection';
          num_intersections = num_intersections - 1;
        END LOOP;
      ELSE
        -- Go to the next intersection after this slice
        WHILE num_intersections > 0 LOOP
          RAISE NOTICE '  Adding addition intersection';
          num_intersections = num_intersections - 1;
        END LOOP;
      END IF;


      -- This could be used to display each node:
      -- RAISE NOTICE 'Skeleton % edge: % to %', skeleton.id, node.parent_location, node.location;
    END LOOP;

    -- The number of nodes per skeleton can now be obtained and displayed with:
    -- SELECT COUNT(*) INTO edge_count FROM skeleton_tree;
    -- RAISE NOTICE 'Skeleton % has % edges', skeleton.id, edge_count;

  END LOOP;

  RAISE NOTICE 'Done populating intersection table for stack %', stack_id;
  RETURN 0;
END;
$$ LANGUAGE plpgsql;

-- Drop the intersection table if it exists
CREATE OR REPLACE FUNCTION intersection_test()
RETURNS void AS $$
BEGIN
  PERFORM recreate_intersection_table('catmaid_skeleton_intersections');
  PERFORM populate_intersection_table(1,1, 'catmaid_skeleton_intersections');
  RETURN;
END;
$$ LANGUAGE plpgsql;
