export const EDIT_COMMAND_CONTRACT_VERSION = 1;

export type EditCommandName =
  | "create_wall"
  | "insert_door"
  | "insert_window"
  | "delete_element"
  | "set_wall_axis"
  | "update_wall_properties"
  | "update_door_properties"
  | "update_window_properties"
  | "move_hosted_opening";

export type EditArtifactPaths = {
  project_json?: string;
  debug_report_json?: string;
  floorplan_svg?: string;
  walls_obj?: string;
  metadata_json?: string;
  render_scene_json?: string;
};

export type EditValidationSummary = {
  errors: number;
  warnings: number;
};

export type EditRouteResponse = {
  success: boolean;
  command: EditCommandName;
  message: string;
  validation: EditValidationSummary;
  updatedFiles: string[];
  output: string;
  error: string | null;
  artifactPaths?: EditArtifactPaths;
  commandOutput?: unknown;
};

export type EditRouteEnvelope = {
  status: number;
  body: EditRouteResponse;
};
