require 'rdf'
require 'rdf/turtle'
require 'json'

file_path = 'datatourism.ontology.ttl'
graph = RDF::Graph.load(file_path)

output = {
  name: 'Datatourisme Ontology',
  group: {},
  properties_extra: {}
}

h = Hash.new { |hash, key| hash[key] = { group: {} } }

@lang_map = {
  'en' => 'en-US',
  'fr' => 'fr-FR',
  'es' => 'es-ES',
  'pt' => 'pt-PT',
  'it' => 'it-IT',
  'nl' => 'nl-NL',
  'de' => 'de-DE',
}

def lang(col)
  col.collect.to_h{ |y|
    [@lang_map[y.object.language.to_s], y.object.to_s]
  }
end

graph.query([nil, RDF.type, RDF::OWL.Class]) do |statement|
  uri = statement.subject.to_s.split('#').last
  sub_class_of = graph.query([statement.subject, RDF::RDFS.subClassOf, nil]).collect{ |y| y.object.to_s }
  label = lang(graph.query([statement.subject, RDF::RDFS.label, nil]))
  comment = lang(graph.query([statement.subject, RDF::RDFS.comment, nil]))

  sub_class_of = sub_class_of.select{ |sco|
    !sco.start_with?('_:') && !sco.start_with?('http://schema.org')
  }.collect{ |sco|
    sco.split('#').last
  }

  h[uri][:label] = label
  h[uri][:comment] = comment if !comment.empty?

  sub_class_of.each{ |sco|
    h[sco][:group][uri] = h[uri]
  }
end

output[:group] = h['PointOfInterest'][:group]

# puts h['Amenity'][:group].keys

puts JSON.pretty_generate(output)
