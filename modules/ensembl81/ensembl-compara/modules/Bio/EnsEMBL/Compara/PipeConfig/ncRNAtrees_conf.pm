=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=head1 NAME

Bio::EnsEMBL::Compara::PipeConfig::ncRNAtrees_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::ncRNAtrees_conf -password <your_password>

=head1 DESCRIPTION  

This is the Ensembl PipeConfig for the ncRNAtree pipeline.
An example of use can be found in the Example folder.

=head1 AUTHORSHIP

Ensembl Team. Individual contributions can be found in the GIT log.

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with an underscore (_)

=cut

package Bio::EnsEMBL::Compara::PipeConfig::ncRNAtrees_conf ;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version 2.3;

use Bio::EnsEMBL::Compara::PipeConfig::CAFE_conf;

use base ('Bio::EnsEMBL::Compara::PipeConfig::ComparaGeneric_conf');

sub default_options {
    my ($self) = @_;
    return {
        %{$self->SUPER::default_options},

            # User details
            #'email'                 => 'john.smith@example.com',

            # dependent parameters ('work_dir' should be defined)
            'dump_dir'              => $self->o('work_dir') . '/dumps',
            'ss_picts_dir'          => $self->o('work_dir') . '/ss_picts/',

            # tree break
            'treebreak_tags_to_copy'   => ['clustering_id', 'model_name'],

            # misc parameters
            'species_tree_input_file'  => '',  # empty value means 'create using genome_db+ncbi_taxonomy information'; can be overriden by a file with a tree in it
            'skip_epo'                 => 0,   # Never tried this one. It may fail
            'create_ss_pics'           => 0,

            # ambiguity codes
            'allow_ambiguity_codes'    => 0,

            # Do we want to initialise the CAFE part now ?
            'initialise_cafe_pipeline'  => undef,
            # Data needed for CAFE
            'cafe_lambdas'             => '',  # For now, we don't supply lambdas
            'cafe_struct_tree_str'     => '',  # Not set by default
            'full_species_tree_label'  => 'full_species_tree',
            'per_family_table'         => 0,
            'cafe_species'             => [],

           };
}

sub pipeline_create_commands {
    my ($self) = @_;
    return [
            @{$self->SUPER::pipeline_create_commands},  # here we inherit creation of database, hive tables and compara tables

            'mkdir -p '.$self->o('work_dir'),
            'mkdir -p '.$self->o('dump_dir'),
            'mkdir -p '.$self->o('ss_picts_dir'),
    ];
}


sub pipeline_wide_parameters {  # these parameter values are visible to all analyses, can be overridden by parameters{} and input_id{}
    my ($self) = @_;
    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class

        'mlss_id'       => $self->o('mlss_id'),
        'master_db'     => $self->o('master_db'),
    }
}


sub pipeline_analyses {
    my ($self) = @_;

    my %hc_params = (
                     -analysis_capacity => $self->o('hc_capacity'),
                     -priority          => $self->o('hc_priority'),
                     -bacth_size        => $self->o('hc_batch_size'),
                    );

    my %backbone_params = (
                           -meadow_type       => 'LOCAL',
                          );

    my $analyses_species_tree = Bio::EnsEMBL::Compara::PipeConfig::CAFE_conf::pipeline_analyses_species_tree($self);
    my $analyses_cafe = Bio::EnsEMBL::Compara::PipeConfig::CAFE_conf::pipeline_analyses_cafe($self);

    return [

# --------------------------------------------- [ backbone ]-----------------------------------------------------------------------------
            {   -logic_name => 'backbone_fire_db_prepare',
                -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
                -input_ids  => [ {} ],
                -flow_into  => {
                                '1->A'  => [ 'copy_table_factory' ],
                                'A->1'  => [ 'backbone_fire_load' ],
                               },
                %backbone_params,
            },

            {   -logic_name => 'backbone_fire_load',
                -module     => 'Bio::EnsEMBL::Hive::RunnableDB::DatabaseDumper',
                -parameters  => {
                                  'output_file'          => $self->o('dump_dir').'/snapshot_before_load.sql',
                                },
                -flow_into  => {
                               '1->A'   => [ 'load_genomedb_factory' ],
                               'A->1'   => [ 'backbone_fire_tree_building' ],
                              },
                %backbone_params,
            },

            {   -logic_name => 'backbone_fire_tree_building',
                -module     => 'Bio::EnsEMBL::Hive::RunnableDB::DatabaseDumper',
                -parameters  => {
                                  'output_file'          => $self->o('dump_dir').'/snapshot_before_tree_building.sql',
                                 },
                -flow_into  => {
                                '1->A'  => [ 'rfam_classify' ],
                                'A->1'  => [ 'backbone_pipeline_finished' ],
                               },
                %backbone_params,
            },

            {   -logic_name => 'backbone_pipeline_finished',
                -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
                %backbone_params,
            },

# ---------------------------------------------[copy tables from master and fix the offsets]---------------------------------------------

        {   -logic_name => 'copy_table_factory',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'db_conn'   => '#master_db#',
                'inputlist' => [ 'method_link', 'species_set', 'method_link_species_set', 'ncbi_taxa_name', 'ncbi_taxa_node', 'dnafrag' ],
                'column_names' => [ 'table' ],
            },

            -flow_into => {
                           '2->A' => { 'copy_table' => { 'src_db_conn' => '#db_conn#', 'table' => '#table#' } },
                           'A->1' => [ 'offset_tables' ],
            },
        },

            {   -logic_name    => 'copy_table',
                -module        => 'Bio::EnsEMBL::Hive::RunnableDB::MySQLTransfer',
                -parameters    => {
                                   'mode'          => 'overwrite',
                                   'filter_cmd'    => 'sed "s/ENGINE=MyISAM/ENGINE=InnoDB/"',
                                  },
                -analysis_capacity => 10,
                -flow_into         => [ 'innodbise_table' ],
            },

        {   -logic_name => 'offset_tables',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SqlCmd',
            -parameters => {
                'sql'   => [
                    'ALTER TABLE gene_member       AUTO_INCREMENT=100000001',
                    'ALTER TABLE seq_member        AUTO_INCREMENT=100000001',
                    'ALTER TABLE sequence          AUTO_INCREMENT=100000001',
                    'ALTER TABLE homology          AUTO_INCREMENT=100000001',
                    'ALTER TABLE gene_align        AUTO_INCREMENT=100000001',
                    'ALTER TABLE gene_tree_node    AUTO_INCREMENT=100000001',
                    'ALTER TABLE CAFE_gene_family  AUTO_INCREMENT=100000001',
                    'ALTER TABLE CAFE_species_gene AUTO_INCREMENT=100000001',
                ],
            },
        },

# ---------------------------------------------[turn all tables to InnoDB]---------------------------------------------

        {   -logic_name    => 'innodbise_table',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SqlCmd',
            -parameters    => {
                'sql'         => "ALTER TABLE #table# ENGINE=InnoDB",
            },
            -analysis_capacity => 10,
        },

# ---------------------------------------------[load GenomeDB entries from master+cores]---------------------------------------------

            {   -logic_name => 'load_genomedb_factory',
                -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GenomeDBFactory',
                -parameters => {
                                'compara_db'            => '#master_db#',   # that's where genome_db_ids come from
                                'extra_parameters'      => [ 'locator' ],
                               },
                -flow_into => {
                               '2->A' => { 'load_genomedb' => { 'master_dbID' => '#genome_db_id#', 'locator' => '#locator#' }, }, # fan
                               'A->1' => [ 'load_genomedb_funnel' ],
                               1      => [ 'load_rfam_models' ],
                              },
            },

        {   -logic_name => 'load_genomedb',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::LoadOneGenomeDB',
            -parameters => {
                            'registry_dbs'   => [ $self->o('reg1'), $self->o('reg2') ],
            },
            -analysis_capacity => 10,
        },


        {   -logic_name         => 'hc_members_per_genome',
            -module             => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::SqlHealthChecks',
            -parameters         => {
                mode            => 'members_per_genome',
                allow_missing_coordinates   => 0,
                allow_missing_cds_seqs => 0,
                allow_ambiguity_codes => $self->o('allow_ambiguity_codes'),
            },
            -flow_into  => [ 'per_genome_qc' ],
            %hc_params,
        },

        {   -logic_name => 'load_members_factory',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GenomeDBFactory',
            -flow_into  => {
                '2->A' => 'load_members',
                'A->1' => [ 'hc_members_globally' ],
            },
        },

        {   -logic_name => 'per_genome_qc',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::PerGenomeGroupsetQC',
            -rc_name    => '4Gb_job',
        },

        {   -logic_name => 'load_genomedb_funnel',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SqlCmd',
            -parameters => {
                            # Removes the SS and the MLSS associated with non-valid genome_db_ids
                            'sql' => [ 'CREATE TEMPORARY TABLE tmp_ss SELECT species_set_id FROM species_set LEFT JOIN genome_db USING (genome_db_id) GROUP BY species_set_id HAVING COUNT(*) != COUNT(genome_db.genome_db_id)',
                                       'DELETE method_link_species_set FROM method_link_species_set JOIN tmp_ss USING (species_set_id)',
                                       'DELETE species_set FROM species_set JOIN tmp_ss USING (species_set_id)',
                                     ]
                           },
            -flow_into  => [ 'make_species_tree' ],
        },

        {   -logic_name         => 'hc_members_globally',
            -module             => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::SqlHealthChecks',
            -parameters         => {
                mode            => 'members_globally',
            },
            %hc_params,
            -flow_into  => [ 'register_mlss' ],
        },


        {   -logic_name         => 'register_mlss',
            -module             => 'Bio::EnsEMBL::Compara::RunnableDB::RegisterMLSS',
        },

# ---------------------------------------------[load species tree]-------------------------------------------------------------------


        {   -logic_name    => 'make_species_tree',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::MakeSpeciesTree',
            -parameters    => {
                'species_tree_input_file'               => $self->o('species_tree_input_file'),   # empty by default, but if nonempty this file will be used instead of tree generation from genome_db
                'multifurcation_deletes_node'           => [ 314146, 1489913 ], # 33316 and 129949 has been removed from NCBI taxonomy
                'multifurcation_deletes_all_subnodes'   => [  9347, 186625,  32561 ],
            },
            -flow_into     => {
                2 => [ 'hc_species_tree' ],
            }
        },

        {   -logic_name         => 'hc_species_tree',
            -module             => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::SqlHealthChecks',
            -parameters         => {
                mode            => 'species_tree',
                binary          => 0,
            },
            -flow_into          => [ 'load_members_factory', $self->o('initialise_cafe_pipeline') ? ('make_full_species_tree') : (), $self->o('skip_epo') ? () : ('find_epo_database') ],
            %hc_params,
        },

# ---------------------------------------------[create the low-coverage-assembly species set]-----------------------------------------

        {   -logic_name => 'find_epo_database',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::FindMLSS',
            -parameters => {
                method_links => {
                    EPO_LOW_COVERAGE => 'epo_db',
                },
                species_set_name => $self->o('epo_species_set_name'),
            },
            -flow_into => [ 'generate_pre_species_set' ],
        },

        {   -logic_name => 'generate_pre_species_set',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'db_conn'         => '#epo_db#',
                'inputquery'      => "SELECT GROUP_CONCAT(DISTINCT g.genome_db_id) AS genome_db_ids FROM genome_db g JOIN species_set ss USING(genome_db_id) JOIN method_link_species_set mlss USING(species_set_id) WHERE assembly_default AND mlss.name LIKE '%EPO_LOW_COVERAGE%' AND g.genome_db_id NOT IN (SELECT DISTINCT(g2.genome_db_id) FROM genome_db g2 JOIN species_set ss2 USING(genome_db_id) JOIN method_link_species_set mlss2 USING(species_set_id) WHERE assembly_default AND mlss2.name LIKE '%EPO')",
            },
            -flow_into => {
                           2 => [ 'store_lca_species_set' ],
            },
        },

        {   -logic_name => 'store_lca_species_set',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::StoreLowCovSpeciesSet',
        },

# ---------------------------------------------[load ncRNA and gene members]---------------------------------------------

        {   -logic_name        => 'load_members',
            -module            => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::GenomeStoreNCMembers',
            -analysis_capacity => 10,
            -rc_name           => '2Gb_job',
            -flow_into         => [ 'hc_members_per_genome' ],
        },

# ---------------------------------------------[load RFAM models]---------------------------------------------------------------------

        {   -logic_name    => 'load_rfam_models',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::ComparaHMM::MultiHMMLoadModels',
            -parameters    => {
                               'url'               => $self->o('rfam_ftp_url'),
                               'remote_file'       => $self->o('rfam_remote_file'),
                               'expanded_basename' => $self->o('rfam_expanded_basename'),
                               'expander'          => $self->o('rfam_expander'),
                               'type'              => 'infernal',
                               'skip_consensus'    => 1,
                              },
        },

# ---------------------------------------------[run RFAM classification]--------------------------------------------------------------

            {   -logic_name    => 'rfam_classify',
                -module        => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::RFAMClassify',
                -flow_into     => {
                                   '1->A' => ['create_additional_clustersets'],
                                   'A->1' => ['clusters_factory'],
                                  },
                -rc_name       => '1Gb_job',
            },


            {   -logic_name    => 'create_additional_clustersets',
                -module        => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::CreateClustersets',
                -parameters    => {
                                   'member_type'            => 'ncrna',
                                   'additional_clustersets' => [qw(pg_it_nj ml_it_10 pg_it_phyml ss_it_s16 ss_it_s6a ss_it_s16a ss_it_s6b ss_it_s16b ss_it_s6c ss_it_s6d ss_it_s6e ss_it_s7a ss_it_s7b ss_it_s7c ss_it_s7d ss_it_s7e ss_it_s7f ft_it_ml ft_it_nj ftga_it_ml ftga_it_nj)],
                                  },
            },


            {   -logic_name    => 'clusters_factory',
                -module        => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
                -parameters => {
                                'inputquery'      => 'SELECT root_id AS gene_tree_id FROM gene_tree_root JOIN gene_tree_node USING (root_id) WHERE tree_type = "tree" GROUP BY root_id ORDER BY COUNT(*) DESC, root_id ASC',
                               },
                -flow_into     => {
                                   '2->A' => ['clusterset_backup'],
                                   'A->1' => [ 'hc_tree_final_checks' ],
                                  },
            },


            { -logic_name       => 'hc_tree_final_checks',
              -module           => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
              -flow_into        => {
                                    '1->A' => ['hc_global_tree_set', 'hc_global_epo_removed_members'],
                                    'A->1' => [ 'write_stn_tags' ],
                                   },
              %hc_params,
            },

            { -logic_name         => 'hc_global_tree_set',
              -module             => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::SqlHealthChecks',
              -parameters         => {
                                      mode            => 'global_tree_set',
                                     },
              %hc_params,
            },

            { -logic_name      => 'hc_global_epo_removed_members',
              -module          => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::SqlHealthChecks',
              -parameters      => {
                                   mode => 'epo_removed_members_globally',
                                  },
              %hc_params,
            },

        {   -logic_name     => 'write_stn_tags',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::DbCmd',
            -parameters     => {
                'input_file'    => $self->o('ensembl_cvs_root_dir').'/ensembl-compara/sql/tree-stats-as-stn_tags.sql',
            },
            -flow_into      => [ 'email_tree_stats_report', 'write_member_counts', $self->o('initialise_cafe_pipeline') ? ('CAFE_table') : () ],
        },

        {   -logic_name     => 'email_tree_stats_report',
            -module         => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::HTMLReport',
            -parameters     => {
                'email' => $self->o('email'),
            },
        },

        {   -logic_name     => 'write_member_counts',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::DbCmd',
            -parameters     => {
                'input_file'    => $self->o('ensembl_cvs_root_dir').'/ensembl-compara/scripts/production/populate_member_production_counts_table.sql',
            },
        },

            {   -logic_name    => 'clusterset_backup',
                -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SqlCmd',
                -parameters    => {
                                   'sql'         => 'INSERT INTO gene_tree_backup (seq_member_id, root_id) SELECT seq_member_id, root_id FROM gene_tree_node WHERE seq_member_id IS NOT NULL AND root_id = #gene_tree_id#',
                                  },
                -analysis_capacity => 1,
                -flow_into      => [ $self->o('skip_epo') ? 'msa_chooser' : 'recover_epo' ],
            },


            {   -logic_name    => 'recover_epo',
                -module        => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::NCRecoverEPO',
                -parameters    => {
                    'max_members'   => 10000,
                },
                -analysis_capacity => $self->o('recover_capacity'),
                -flow_into => {
                    1 => 'hc_epo_removed_members',
                    -1 => 'recover_epo_himem',
                },
                -rc_name => '2Gb_job',
            },

            {   -logic_name    => 'recover_epo_himem',
                -module        => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::NCRecoverEPO',
                -analysis_capacity => $self->o('recover_capacity'),
                -flow_into => [ 'hc_epo_removed_members' ],
                -rc_name => '8Gb_long_job',
            },

            {  -logic_name        => 'hc_epo_removed_members',
               -module            => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::SqlHealthChecks',
               -parameters        => {
                                      mode => 'epo_removed_members',
                                     },
               -flow_into         => [ 'msa_chooser' ],
               %hc_params,
            },

            {   -logic_name    => 'msa_chooser',
                -module        => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::MSAChooser',
                -parameters    => {
                                   'treebreak_gene_count'  => $self->o('treebreak_gene_count'),
                                  },
                -batch_size    => 10,
                -rc_name       => '1Gb_job',
                -priority      => 30,
                -analysis_capacity => $self->o('msa_chooser_capacity'),
                -flow_into     => {
                                   '1->A' => [ 'genomic_alignment', 'infernal' ],
                                   'A->1' => [ 'treebest_mmerge' ],
                                   '3->B' => [ 'aligner_for_tree_break' ],
                                   'B->4' => [ 'quick_tree_break' ],
                                  },
            },

            {   -logic_name    => 'aligner_for_tree_break',
                -module        => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::Infernal',
                -analysis_capacity => $self->o('aligner_for_tree_break_capacity'),
                -parameters => {
                                'cmbuild_exe' => $self->o('cmbuild_exe'),
                                'cmalign_exe' => $self->o('cmalign_exe'),
                               },
                -flow_into    => {
                                  1 => [ 'hc_alignment' ],
                                 },
                -rc_name => '2Gb_job',
            },


        {   -logic_name         => 'hc_alignment',
            -module             => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::SqlHealthChecks',
            -parameters         => {
                mode            => 'alignment',
            },
            %hc_params,
        },

            {   -logic_name => 'quick_tree_break',
                -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::QuickTreeBreak',
                -parameters => {
                                'quicktree_exe'     => $self->o('quicktree_exe'),
                                'tags_to_copy'      => $self->o('treebreak_tags_to_copy'),
                                'treebreak_gene_count'  => $self->o('treebreak_gene_count'),
                               },
                -analysis_capacity  => $self->o('quick_tree_break_capacity'),
                -rc_name        => '4Gb_job',
                -priority       => 50,
                -flow_into      => [ 'hc_supertrees' ],
            },

        {   -logic_name         => 'hc_supertrees',
            -module             => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::SqlHealthChecks',
            -parameters         => {
                mode            => 'supertrees',
            },
            -flow_into          => [ 'other_paralogs' ],
            %hc_params,
        },

            {   -logic_name     => 'other_paralogs',
                -module         => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::OtherParalogs',
                -parameters     => {
                                    'dataflow_subclusters' => 1,
                                   },
                -analysis_capacity  => $self->o('other_paralogs_capacity'),
                -rc_name            => '1Gb_job',
                -priority           => 40,
                -flow_into     => {
                                   2 => [ 'tree_backup' ],
                                  },
            },

            {   -logic_name    => 'infernal',
                -module        => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::Infernal',
                -analysis_capacity => $self->o('infernal_capacity'),
                -parameters    => {
                                   'cmbuild_exe' => $self->o('cmbuild_exe'),
                                   'cmalign_exe' => $self->o('cmalign_exe'),
                                  },
                -flow_into     => {
                                   1 => ['pre_sec_struct_tree', 'hc_alignment' ],
                                   3 => $self->o('create_ss_pics') ? ['create_ss_picts'] : [],
                                  },
                -rc_name       => '2Gb_job',
            },

            {   -logic_name    => 'tree_backup',
                -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SqlCmd',
                -parameters    => {
                                   'sql' => 'INSERT INTO gene_tree_backup (seq_member_id, root_id) SELECT seq_member_id, root_id FROM gene_tree_node WHERE seq_member_id IS NOT NULL AND root_id = #gene_tree_id#',
                                  },
                -flow_into => {
                               '1->A' => [ 'genomic_alignment', 'infernal' ],
                               'A->1' => [ 'treebest_mmerge' ],
                              },
                -analysis_capacity => 1,
            },

            $self->o('create_ss_pics') ? (
            {   -logic_name    => 'create_ss_picts',
                -module        => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::GenerateSSPict',
                -analysis_capacity => $self->o('ss_picts_capacity'),
                -parameters    => {
                                   'ss_picts_dir'  => $self->o('ss_picts_dir'),
                                   'r2r_exe'       => $self->o('r2r_exe'),
                                  },
                -failed_job_tolerance =>  30,
                -rc_name       => '2Gb_job',
            },
                                         ) : (), # do not include the ss_pics analysis if the opt is off

            {
             -logic_name    => 'pre_sec_struct_tree', ## pre_sec_struct_tree
             -module        => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::PrepareSecStructModels',  ## PrepareRAxMLSecModels -- rename
             -analysis_capacity => $self->o('raxml_capacity'),
             -parameters => {
                             'raxml_exe'             => $self->o('raxml_exe'),
                             'raxml_number_of_cores' => $self->o('raxml_number_of_cores'),
                            },
             -flow_into => {
                            2 => [ 'sec_struct_model_tree'],
                           },
             -rc_name => '2Gb_ncores_job',
            },

        {   -logic_name    => 'sec_struct_model_tree', ## sec_struct_model_tree
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::SecStructModelTree', ## SecStrucModels
            -analysis_capacity => $self->o('raxml_capacity'),
            -parameters => {
                            'raxml_exe'             => $self->o('raxml_exe'),
                            'raxml_number_of_cores' => $self->o('raxml_number_of_cores'),
                           },
            -rc_name => '2Gb_ncores_job',
        },

        {   -logic_name    => 'genomic_alignment',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::NCGenomicAlignment',
            -analysis_capacity => $self->o('genomic_alignment_capacity'),
            -parameters => {
                            'mafft_exe'             => $self->o('mafft_exe'),
                            'raxml_exe'             => $self->o('raxml_exe'),
                            'raxml_number_of_cores' => $self->o('raxml_number_of_cores'),
                            'prank_exe'             => $self->o('prank_exe'),
                           },
            -flow_into => {
                           -2 => ['genomic_alignment_long'],
                           -1 => ['genomic_alignment_long'],
                           1  => ['hc_alignment' ],
                           3  => ['fast_trees'],
                           2  => ['genomic_tree'],
                          },
            -rc_name => '2Gb_ncores_job',
        },

            {
             -logic_name => 'fast_trees',
             -module => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::NCFastTrees',
             -analysis_capacity => $self->o('fast_trees_capacity'),
             -parameters => {
                             'fasttree_exe'          => $self->o('fasttree_exe'),
                             'parsimonator_exe'      => $self->o('parsimonator_exe'),
                             'raxmlLight_exe'        => $self->o('raxmlLight_exe'),
                             'raxml_number_of_cores' => $self->o('raxml_number_of_cores'),
                            },
             -rc_name => '8Gb_basement_ncores_job',
            },

        {
         -logic_name => 'genomic_alignment_long',
         -module => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::NCGenomicAlignment',
         -analysis_capacity => $self->o('genomic_alignment_capacity'),
            -parameters => {
                            'raxml_number_of_cores' => $self->o('raxml_number_of_cores'),
                            'mafft_exe' => $self->o('mafft_exe'),
                            'raxml_exe' => $self->o('raxml_exe'),
                            'prank_exe' => $self->o('prank_exe'),
                           },
         -rc_name => '8Gb_basement_ncores_job',
         -flow_into => {
                        1 => [ 'hc_alignment' ],
                        2 => [ 'genomic_tree_himem' ],
                       },
        },

            {
             -logic_name => 'genomic_tree',
             -module => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::NCGenomicTree',
             -analysis_capacity => $self->o('genomic_tree_capacity'),
             -parameters => {
                             'treebest_exe' => $self->o('treebest_exe'),
                            },
             -flow_into => {
                            -2 => ['genomic_tree_himem'],
                            -1 => ['genomic_tree_himem'],
                           },
             -rc_name => '2Gb_job',
            },

            {
             -logic_name => 'genomic_tree_himem',
             -module => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::NCGenomicTree',
             -analysis_capacity => $self->o('genomic_tree_capacity'),
             -parameters => {
                             'treebest_exe' => $self->o('treebest_exe'),
                            },
             -rc_name => '4Gb_job',
            },

        {   -logic_name    => 'treebest_mmerge',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::NCTreeBestMMerge',
            -analysis_capacity => $self->o('treebest_capacity'),
            -parameters => {
                            'treebest_exe' => $self->o('treebest_exe'),
                           },
            -flow_into => {
                           '1->A' =>  [ 'hc_alignment_post_tree', 'hc_tree_structure' ],
                           'A->1' => [ 'orthotree' ],
                           1 => [ 'ktreedist' ],
                           '2->A' => [ 'hc_tree_structure' ],
            },
            -rc_name => '2Gb_job',
        },

        {   -logic_name         => 'hc_alignment_post_tree',
            -module             => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::SqlHealthChecks',
            -parameters         => {
                mode            => 'alignment',
            },
            %hc_params,
        },

        {   -logic_name         => 'hc_tree_structure',
            -module             => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::SqlHealthChecks',
            -parameters         => {
                mode            => 'tree_structure',
            },
            %hc_params,
        },

        {   -logic_name    => 'orthotree',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::OrthoTree',
            -analysis_capacity => $self->o('orthotree_capacity'),
            -parameters => {
                            'tag_split_genes'   => 0,
            },
            -flow_into  => [ 'hc_tree_attributes', 'hc_tree_homologies' ],
           -rc_name => '1Gb_job',
        },

        {   -logic_name    => 'ktreedist',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::Ktreedist',
            -parameters => {
                            'treebest_exe'  => $self->o('treebest_exe'),
                            'ktreedist_exe' => $self->o('ktreedist_exe'),
                           },
            -rc_name => '2Gb_job',
        },

        {   -logic_name         => 'hc_tree_attributes',
            -module             => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::SqlHealthChecks',
            -parameters         => {
                mode            => 'tree_attributes',
            },
            %hc_params,
        },

        {   -logic_name         => 'hc_tree_homologies',
            -module             => 'Bio::EnsEMBL::Compara::RunnableDB::GeneTrees::SqlHealthChecks',
            -parameters         => {
                mode            => 'tree_homologies',
            },
            %hc_params,
        },

        @$analyses_species_tree,
        @$analyses_cafe,
    ];
}

1;

