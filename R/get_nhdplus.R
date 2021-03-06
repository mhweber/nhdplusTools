#' @title Discover NHDPlus ID
#' @description Multipurpose function to find a COMID of interest.
#' @param point An sf POINT including crs as created by:
#' sf::st_sfc(sf::st_point(..,..), crs)
#' @param nldi_feature list with names `featureSource` and `featureID` where
#' `featureSource` is derived from the "source" column of  the response of
#' discover_nldi_sources() and the `featureSource` is a known identifier
#' from the specified `featureSource`.
#' @return integer COMID
#' @export
#' @examples
#' \donttest{
#' point <- sf::st_sfc(sf::st_point(c(-76.87479, 39.48233)), crs = 4326)
#' discover_nhdplus_id(point)
#'
#' nldi_nwis <- list(featureSource = "nwissite", featureID = "USGS-08279500")
#' discover_nhdplus_id(nldi_feature = nldi_nwis)
#' }
discover_nhdplus_id <- function(point = NULL, nldi_feature = NULL) {

  if (!is.null(point)) {

    url_base <- paste0("https://cida.usgs.gov/nwc/geoserver/nhdplus/ows",
                       "?service=WFS",
                       "&version=1.0.0",
                       "&request=GetFeature",
                       "&typeName=nhdplus:catchmentsp",
                       "&outputFormat=application%2Fjson",
                       "&srsName=EPSG:4269")
    # "&bbox=40,-90.001,40.001,-90,urn:ogc:def:crs:EPSG:4269",

    p_crd <- sf::st_coordinates(sf::st_transform(point, 4269))

    url <- paste0(url_base, "&bbox=",
                  paste(p_crd[2], p_crd[1],
                        p_crd[2] + 0.00001, p_crd[1] + 0.00001,
                        "urn:ogc:def:crs:EPSG:4269", sep = ","))

    req_data <- httr::RETRY("GET", url, times = 3, pause_cap = 60)

    catchment <- make_web_sf(req_data)

    if (nrow(catchment) > 1) {
      warning("point too close to edge of catchment found multiple.")
    }

    return(as.integer(catchment$featureid))

  } else if (!is.null(nldi_feature)) {

    check_nldi_feature(nldi_feature)

    if (is.null(nldi_feature[["tier"]])) nldi_feature[["tier"]] <- "prod"

    nldi <- get_nldi_feature(nldi_feature,
                             nldi_feature[["tier"]])

    return(as.integer(nldi$comid))

  } else {

    stop("Must provide point or nldi_feature input.")

  }
}

#' @noRd
get_nhdplus_byid <- function(comids, layer) {

  id_name <- list(catchmentsp = "featureid", nhdflowline_network = "comid")

  if (!any(names(id_name) %in% layer)) {
    stop(paste("Layer must be one of",
               paste(names(id_name),
                     collapse = ", ")))
  }

  post_url <- "https://cida.usgs.gov/nwc/geoserver/nhdplus/ows"

  # nolint start

  filter_1 <- paste0('<?xml version="1.0"?>',
                     '<wfs:GetFeature xmlns:wfs="http://www.opengis.net/wfs" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:gml="http://www.opengis.net/gml" service="WFS" version="1.1.0" outputFormat="application/json" xsi:schemaLocation="http://www.opengis.net/wfs http://schemas.opengis.net/wfs/1.1.0/wfs.xsd">',
                     '<wfs:Query xmlns:feature="http://gov.usgs.cida/nhdplus" typeName="feature:',
                     layer, '" srsName="EPSG:4326">',
                     '<ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">',
                     '<ogc:Or>',
                     '<ogc:PropertyIsEqualTo>',
                     '<ogc:PropertyName>',
                     id_name[[layer]],
                     '</ogc:PropertyName>',
                     '<ogc:Literal>')

  filter_2 <- paste0('</ogc:Literal>',
                     '</ogc:PropertyIsEqualTo>',
                     '<ogc:PropertyIsEqualTo>',
                     '<ogc:PropertyName>',
                     id_name[[layer]],
                     '</ogc:PropertyName>',
                     '<ogc:Literal>')

  filter_3 <- paste0('</ogc:Literal>',
                     '</ogc:PropertyIsEqualTo>',
                     '</ogc:Or>',
                     '</ogc:Filter>',
                     '</wfs:Query>',
                     '</wfs:GetFeature>')

  filter_xml <- paste0(filter_1, paste0(comids, collapse = filter_2), filter_3)

  # nolint end

  req_data <- httr::RETRY("POST", post_url, body = filter_xml, times = 3, pause_cap = 60)

  return(make_web_sf(req_data))
}

#' @noRd
get_nhdplus_bybox <- function(box, layer) {

  valid_layers <- c("nhdarea", "nhdwaterbody", "catchmentsp", "nhdflowline_network")

  if (!layer %in% valid_layers) {
    stop(paste("Layer must be one of",
               paste(valid_layers,
                     collapse = ", ")))
  }

  bbox <- sf::st_bbox(sf::st_transform(box, 4326))

  post_url <- "https://cida.usgs.gov/nwc/geoserver/nhdplus/ows"

  # nolint start

  filter_xml <- paste0('<?xml version="1.0"?>',
                       '<wfs:GetFeature xmlns:wfs="http://www.opengis.net/wfs" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:gml="http://www.opengis.net/gml" service="WFS" version="1.1.0" outputFormat="application/json" xsi:schemaLocation="http://www.opengis.net/wfs http://schemas.opengis.net/wfs/1.1.0/wfs.xsd">',
                       '<wfs:Query xmlns:feature="http://gov.usgs.cida/nhdplus" typeName="feature:',
                       layer, '" srsName="EPSG:4326">',
                       '<ogc:Filter xmlns:ogc="http://www.opengis.net/ogc">',
                       '<ogc:BBOX>',
                       '<ogc:PropertyName>the_geom</ogc:PropertyName>',
                       '<gml:Envelope>',
                       '<gml:lowerCorner>',bbox[2]," ",bbox[1],'</gml:lowerCorner>',
                       '<gml:upperCorner>',bbox[4]," ",bbox[3],'</gml:upperCorner>',
                       '</gml:Envelope>',
                       '</ogc:BBOX>',
                       '</ogc:Filter>',
                       '</wfs:Query>',
                       '</wfs:GetFeature>')

  # nolint end

  req_data <- httr::RETRY("POST", post_url, body = filter_xml, times = 3, pause_cap = 60)

  return(make_web_sf(req_data))

}

make_web_sf <- function(content) {
  if(content$status_code == 200) {
    tryCatch(sf::read_sf(rawToChar(content$content)),
             error = function(e) {
               message(paste("Something went wrong with a web request.\n", e))
             }, warning = function(w) {
               message(paste("Something went wrong with a web request.\n", w))
             })
  } else {
    message(paste("Something went wrong with a web request.\n", content$url,
                  "\n", "returned",
                  content$status_code))
    data.frame()
  }
}
